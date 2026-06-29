//
//  ContainersListView.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct ContainersListView: View {
    @Binding var selection: String?
    @Environment(ContainersStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidate: String?

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.containers, id: \.id) { container in
                ContainerRow(container: container)
                    .tag(container.id)
                    .contextMenu { rowMenu(container) }
            }
        }
        .contextMenu { Button(SidebarSection.containers.newItemLabel) { showCreateSheet = true } }
        .overlay {
            if store.containers.isEmpty {
                ContentUnavailableView {
                    Label("No Containers", systemImage: "shippingbox")
                } description: {
                    Text("Create a container from an image, or start one with the container CLI.")
                } actions: {
                    Button("New Container…") { showCreateSheet = true }
                }
            }
        }
        .navigationTitle("Containers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Container", systemImage: "plus")
                }
                .help("Create a new container")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            ContainerCreateSheet()
        }
        .confirmationDialog(
            "Delete the container “\(deleteCandidate ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteCandidate { Task { await store.delete(id: id, force: true) } }
                deleteCandidate = nil
            }
        } message: {
            Text("This permanently removes the container.")
        }
        .errorAlert($store.lastError)
        .onAppear(perform: consumeCreate)
        .onChange(of: router.pendingCreate) { consumeCreate() }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }

    @ViewBuilder
    private func rowMenu(_ container: ContainerSnapshot) -> some View {
        if container.status == .running {
            Button("Stop") { Task { await store.stop(id: container.id) } }
            Button("Open Terminal") { router.openTerminal(id: container.id, in: .containers) }
            Button("Open in Terminal.app") { openInTerminalApp(container.id) }
        } else {
            Button("Start") { Task { await store.start(id: container.id) } }
        }
        Divider()
        Button("Delete…", role: .destructive) { deleteCandidate = container.id }
    }

    private func openInTerminalApp(_ id: String) {
        Task {
            switch await TerminalLauncher.openContainerShell(containerId: id) {
            case .opened, .openedViaFallback:
                break
            case .automationDenied:
                store.lastError = PresentedError(
                    title: "Terminal access needed",
                    message: "Enable ContainerManager under Automation in Privacy & Security settings, then try again."
                )
            case .failed(let message):
                store.lastError = PresentedError(title: "Failed to open Terminal", message: message)
            }
        }
    }

    private func consumeCreate() {
        if router.pendingCreate == .containers {
            showCreateSheet = true
            router.pendingCreate = nil
        }
    }
}

struct ContainerRow: View {
    let container: ContainerSnapshot

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: container.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.id)
                    .fontWeight(.medium)
                Text(container.configuration.image.reference.shortImageReference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let attachment = container.networks.first {
                Text("\(attachment.ipv4Address)".withoutCIDRSuffix)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
