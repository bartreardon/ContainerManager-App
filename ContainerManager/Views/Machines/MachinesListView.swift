//
//  MachinesListView.swift
//  ContainerManager
//

import AppKit
import ContainerResource
import MachineAPIClient
import SwiftUI

struct MachinesListView: View {
    @Binding var selection: Set<String>
    @Environment(MachinesStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""

    private var machines: [MachineSnapshot] {
        guard !searchText.isEmpty else { return store.machines }
        return store.machines.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.configuration.image.reference.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(machines, id: \.id) { machine in
                MachineRow(machine: machine, isDefault: machine.id == store.defaultId)
                    .tag(machine.id)
                    .draggable(machine.id)
                    .copyable([machine.id])
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter machines")
        .overlay {
            if store.machines.isEmpty {
                ContentUnavailableView {
                    Label("No Machines", systemImage: "desktopcomputer")
                } description: {
                    Text("Create a container machine to get a persistent Linux environment that feels like part of your Mac.")
                } actions: {
                    Button("New Machine…") { showCreateSheet = true }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Machine", systemImage: "plus")
                }
                .help("Create a new container machine")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            MachineCreateSheet()
        }
        .confirmationDialog(
            deleteCandidates.count > 1
                ? "Delete \(deleteCandidates.count) machines?"
                : "Delete the machine “\(deleteCandidates.first ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                let ids = deleteCandidates
                Task { for id in ids { await store.delete(id: id) } }
                deleteCandidates = []
            }
        } message: {
            Text("Each machine will be stopped and its disk contents permanently removed.")
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
            Button(SidebarSection.machines.newItemLabel) { showCreateSheet = true }
        } else {
            Button("Start") { Task { for id in ids { await store.boot(id: id) } } }
            Button("Stop") { Task { for id in ids { await store.stop(id: id) } } }
            if ids.count == 1, let id = ids.first {
                Button("Open Terminal") { router.openTerminal(id: id, in: .machines) }
                Button("Open in Terminal.app") { openInTerminalApp(id) }
                if store.defaultId != id {
                    Button("Set as Default") { Task { await store.setDefault(id: id) } }
                }
            }
            Button(ids.count > 1 ? "Copy Names" : "Copy Name") { Pasteboard.copy(ids.sorted()) }
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidates = ids }
        }
    }

    private func openInTerminalApp(_ id: String) {
        Task {
            switch await TerminalLauncher.openMachineShell(machineId: id) {
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
        if router.pendingCreate == .machines {
            showCreateSheet = true
            router.pendingCreate = nil
        }
    }
}

struct MachineRow: View {
    let machine: MachineSnapshot
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: machine.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(machine.id)
                        .fontWeight(.medium)
                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .help("Default machine")
                    }
                }
                Text(machine.configuration.image.reference.shortImageReference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let ip = machine.ipAddress {
                Text(ip)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
