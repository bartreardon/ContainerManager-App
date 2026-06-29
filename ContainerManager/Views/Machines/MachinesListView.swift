//
//  MachinesListView.swift
//  ContainerManager
//

import ContainerResource
import MachineAPIClient
import SwiftUI

struct MachinesListView: View {
    @Binding var selection: String?
    @Environment(MachinesStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidate: String?

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.machines, id: \.id) { machine in
                MachineRow(machine: machine, isDefault: machine.id == store.defaultId)
                    .tag(machine.id)
                    .contextMenu { rowMenu(machine) }
            }
        }
        .contextMenu { Button(SidebarSection.machines.newItemLabel) { showCreateSheet = true } }
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
        .navigationTitle("Machines")
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
            "Delete the machine “\(deleteCandidate ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteCandidate { Task { await store.delete(id: id) } }
                deleteCandidate = nil
            }
        } message: {
            Text("The machine will be stopped and its disk contents permanently removed.")
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
    private func rowMenu(_ machine: MachineSnapshot) -> some View {
        if machine.status == .running {
            Button("Stop") { Task { await store.stop(id: machine.id) } }
        } else {
            Button("Start") { Task { await store.boot(id: machine.id) } }
        }
        Button("Open Terminal") { router.openTerminal(id: machine.id, in: .machines) }
        Button("Open in Terminal.app") { openInTerminalApp(machine.id) }
        if store.defaultId != machine.id {
            Button("Set as Default") { Task { await store.setDefault(id: machine.id) } }
        }
        Divider()
        Button("Delete…", role: .destructive) { deleteCandidate = machine.id }
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
