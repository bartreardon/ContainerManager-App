//
//  MachineDetailView.swift
//  ContainerManager
//

import ContainerPersistence
import ContainerResource
import MachineAPIClient
import SwiftUI
import struct ContainerizationOCI.Platform

struct MachineDetailView: View {
    let machineId: String?
    @Environment(MachinesStore.self) private var store

    var body: some View {
        if let machineId, let machine = store.machine(withId: machineId) {
            MachineDetailContent(machine: machine)
        } else {
            ContentUnavailableView("Select a Machine", systemImage: "desktopcomputer")
        }
    }
}

private struct MachineDetailContent: View {
    let machine: MachineSnapshot
    @Environment(MachinesStore.self) private var store
    @State private var showDeleteConfirmation = false
    @State private var showLogs = false
    @State private var shellError: PresentedError?
    @State private var showAutomationHelp = false

    private var isBusy: Bool {
        store.isBusy(machine.id)
    }

    var body: some View {
        Form {
            Section("Status") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        StatusDot(status: machine.status)
                        Text(machine.status.rawValue.capitalized)
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                if let ip = machine.ipAddress {
                    LabeledContent("IP Address", value: ip)
                }
                if let started = machine.startedDate {
                    LabeledContent("Started", value: started.formatted(.relative(presentation: .named)))
                }
                if let created = machine.createdDate {
                    LabeledContent("Created", value: created.formatted(date: .abbreviated, time: .shortened))
                }
                if let disk = machine.diskSize {
                    LabeledContent("Disk Usage", value: Format.bytes(disk))
                }
                LabeledContent("Initialized", value: machine.initialized ? "Yes" : "No")
            }
            Section("Image") {
                LabeledContent("Reference", value: machine.configuration.image.reference.shortImageReference)
                LabeledContent("Platform", value: "\(machine.platform.os)/\(machine.platform.architecture)")
                LabeledContent(
                    "User",
                    value: "\(machine.configuration.userSetup.username) (\(machine.configuration.userSetup.uid):\(machine.configuration.userSetup.gid))"
                )
            }
            BootConfigSection(machine: machine)
        }
        .formStyle(.grouped)
        .navigationTitle(machine.id)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if machine.status == .running {
                    Button {
                        Task { await store.stop(id: machine.id) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Stop this machine")
                    .disabled(isBusy)
                } else {
                    Button {
                        Task { await store.boot(id: machine.id) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .help("Start this machine")
                    .disabled(isBusy || machine.status == .stopping)
                }
                Button {
                    Task { await openShell() }
                } label: {
                    Label("Open Shell", systemImage: "terminal")
                }
                .help("Open an interactive shell in Terminal")
                Button {
                    showLogs = true
                } label: {
                    Label("Logs", systemImage: "text.alignleft")
                }
                .help("View machine logs")
                Menu {
                    Button("Set as Default") {
                        Task { await store.setDefault(id: machine.id) }
                    }
                    .disabled(store.defaultId == machine.id)
                    Divider()
                    Button("Delete…", role: .destructive) {
                        showDeleteConfirmation = true
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Delete the machine “\(machine.id)”?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task { await store.delete(id: machine.id) }
            }
        } message: {
            Text("The machine will be stopped and its disk contents permanently removed.")
        }
        .sheet(isPresented: $showLogs) {
            LogsSheet(title: "\(machine.id) Logs", hasBootLog: true) {
                try await MachineClient().logs(id: machine.id)
            }
        }
        .errorAlert($shellError)
        .alert("Terminal Automation Needed", isPresented: $showAutomationHelp) {
            Button("Open System Settings") {
                TerminalLauncher.openAutomationSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("ContainerManager needs permission to control Terminal to open a shell. Enable ContainerManager under Automation in Privacy & Security settings, then try again.")
        }
    }

    private func openShell() async {
        switch await TerminalLauncher.openMachineShell(machineId: machine.id) {
        case .opened, .openedViaFallback:
            break
        case .automationDenied:
            showAutomationHelp = true
        case .failed(let message):
            shellError = PresentedError(title: "Failed to open shell", message: message)
        }
    }
}

private struct BootConfigSection: View {
    let machine: MachineSnapshot
    @Environment(MachinesStore.self) private var store
    @State private var cpus: Int = MachineConfig.defaultCPUs
    @State private var memory: String = ""
    @State private var homeMount: MachineConfig.HomeMountOption = .rw
    @State private var isApplying = false

    private var hasChanges: Bool {
        cpus != machine.bootConfig.cpus
            || memory != machine.bootConfig.memory.formatted
            || homeMount != machine.bootConfig.homeMount
    }

    var body: some View {
        Section {
            Stepper(value: $cpus, in: 1...64) {
                LabeledContent("CPUs", value: "\(cpus)")
            }
            TextField("Memory", text: $memory, prompt: Text("e.g. 4gb"))
            Picker("Home Directory", selection: $homeMount) {
                Text("Read & Write").tag(MachineConfig.HomeMountOption.rw)
                Text("Read Only").tag(MachineConfig.HomeMountOption.ro)
                Text("Not Mounted").tag(MachineConfig.HomeMountOption.none)
            }
            if hasChanges {
                HStack {
                    Button("Apply") {
                        Task {
                            isApplying = true
                            _ = await store.applyBootConfig(
                                id: machine.id,
                                cpus: cpus,
                                memory: memory,
                                homeMount: homeMount
                            )
                            isApplying = false
                        }
                    }
                    .disabled(isApplying)
                    Button("Revert") {
                        load()
                    }
                    .disabled(isApplying)
                }
            }
        } header: {
            Text("Boot Configuration")
        } footer: {
            Text("Changes take effect the next time the machine boots.")
        }
        .onAppear {
            load()
        }
        .onChange(of: machine.id) {
            load()
        }
    }

    private func load() {
        cpus = machine.bootConfig.cpus
        memory = machine.bootConfig.memory.formatted
        homeMount = machine.bootConfig.homeMount
    }
}
