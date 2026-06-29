//
//  MachineDetailView.swift
//  ContainerManager
//

import ContainerPersistence
import ContainerResource
import MachineAPIClient
import SwiftUI
import struct ContainerizationOCI.Platform

private enum MachineDetailMode: String, CaseIterable {
    case info = "Details"
    case terminal = "Terminal"
}

struct MachineDetailView: View {
    let machineId: String?
    @Environment(MachinesStore.self) private var store

    var body: some View {
        if let machineId, let machine = store.machine(withId: machineId) {
            MachineDetailContent(machine: machine)
                .id(machine.id)
        } else {
            ContentUnavailableView("Select a Machine", systemImage: "desktopcomputer")
        }
    }
}

private struct MachineDetailContent: View {
    let machine: MachineSnapshot
    @Environment(MachinesStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var mode: MachineDetailMode = .info
    @State private var terminalSessionId = UUID()
    @State private var terminalExited = false
    @State private var showDeleteConfirmation = false
    @State private var showLogs = false
    @State private var shellError: PresentedError?
    @State private var showAutomationHelp = false

    private var isBusy: Bool {
        store.isBusy(machine.id)
    }

    var body: some View {
        Group {
            switch mode {
            case .info: infoForm
            case .terminal: terminalPane
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                startStopButton
            }
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(MachineDetailMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            machineActions
        }
        .onChange(of: mode) {
            if mode == .terminal {
                terminalExited = false
                terminalSessionId = UUID()
            }
        }
        .onAppear(perform: consumeTerminalRequest)
        .onChange(of: router.openTerminalForId) { consumeTerminalRequest() }
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

    /// Opens the Terminal tab when the sidebar/list/menu requested a shell for this machine.
    private func consumeTerminalRequest() {
        if router.openTerminalForId == machine.id {
            mode = .terminal
            router.openTerminalForId = nil
        }
    }

    private var terminalPane: some View {
        VStack(spacing: 0) {
            EmbeddedTerminalView(
                executable: CLIRunner.containerBinary,
                arguments: ["machine", "run", "--name", machine.id],
                workingDirectory: FileManager.default.homeDirectoryForCurrentUser.path
            ) { _ in
                terminalExited = true
            }
            .id(terminalSessionId)
            .accessibilityLabel("Terminal for \(machine.id)")
            if terminalExited {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle")
                        .foregroundStyle(.secondary)
                    Text("Session ended. The machine keeps running.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Reconnect") {
                        terminalExited = false
                        terminalSessionId = UUID()
                    }
                }
                .padding(8)
                .background(.bar)
            }
        }
    }

    private var infoForm: some View {
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
    }

    /// Start/Stop lives on the leading edge of the toolbar, well away from the
    /// "Open in Terminal" action, so reaching for a shell can't accidentally stop
    /// the machine.
    @ViewBuilder
    private var startStopButton: some View {
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
    }

    @ToolbarContentBuilder
    private var machineActions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                Task { await openShell() }
            } label: {
                Label("Open in Terminal", systemImage: "macwindow")
            }
            .help("Open an interactive shell in Terminal.app")
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
