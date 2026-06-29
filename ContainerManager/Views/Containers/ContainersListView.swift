//
//  ContainersListView.swift
//  ContainerManager
//

import AppKit
import ContainerResource
import SwiftUI

struct ContainersListView: View {
    @Binding var selection: Set<String>
    @Environment(ContainersStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""

    private var containers: [ContainerSnapshot] {
        guard !searchText.isEmpty else { return store.containers }
        return store.containers.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.configuration.image.reference.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(containers, id: \.id) { container in
                ContainerRow(container: container)
                    .tag(container.id)
                    .draggable(container.id)
                    .copyable([container.id])
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter containers")
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
            deleteCandidates.count > 1
                ? "Delete \(deleteCandidates.count) containers?"
                : "Delete the container “\(deleteCandidates.first ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                let ids = deleteCandidates
                Task { for id in ids { await store.delete(id: id, force: true) } }
                deleteCandidates = []
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
                try? await Task.sleep(for: AppDefaults.listRefresh)
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { !deleteCandidates.isEmpty }, set: { if !$0 { deleteCandidates = [] } })
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        if ids.isEmpty {
            Button(SidebarSection.containers.newItemLabel) { showCreateSheet = true }
        } else {
            let running = ids.filter { store.container(withId: $0)?.status == .running }
            if running.count < ids.count {
                Button("Start") { Task { for id in ids { await store.start(id: id) } } }
            }
            if !running.isEmpty {
                Button("Stop") { Task { for id in running { await store.stop(id: id) } } }
            }
            if ids.count == 1, let id = ids.first, store.container(withId: id)?.status == .running {
                Button("Open Terminal") { router.openTerminal(id: id, in: .containers) }
                Button("Open in Terminal.app") { openInTerminalApp(id) }
            }
            Button(ids.count > 1 ? "Copy Names" : "Copy Name") { Pasteboard.copy(ids.sorted()) }
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidates = ids }
        }
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
