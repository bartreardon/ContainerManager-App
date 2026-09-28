//
//  SettingsView.swift
//  ContainerManager
//

import AppKit
import ContainerAPIClient
import ContainerResource
import SwiftUI

/// App preferences (⌘,). Keys are shared with the rest of the app via `@AppStorage`:
/// `containerBinaryPath` is read by `CLIPathResolver`; `listRefreshSeconds` by the lists.
struct SettingsView: View {
    @AppStorage(CLIPathResolver.overrideKey) private var cliPath = ""
    @AppStorage(AppDefaults.listRefreshKey) private var refreshSeconds = 5
    @AppStorage(AppDefaults.statsRefreshKey) private var statsSeconds = 2
    @AppStorage(AppDefaults.updateCheckFrequencyKey) private var updateFrequency = UpdateCheckFrequency.weekly.rawValue
    @AppStorage(AppDefaults.showMenuBarIconKey) private var showMenuBarIcon = true
    @AppStorage(AppDefaults.notificationsEnabledKey) private var notificationsEnabled = false
    @AppStorage(AppDefaults.notifyStopsKey) private var notifyStops = true
    @AppStorage(AppDefaults.notifyOperationsKey) private var notifyOperations = true
    @AppStorage(AppDefaults.notifyThresholdsKey) private var notifyThresholds = true
    @AppStorage(AppDefaults.watchIntervalKey) private var watchSeconds = 30
    @AppStorage(AppDefaults.cpuThresholdKey) private var cpuThreshold = 0
    @AppStorage(AppDefaults.freeDiskThresholdKey) private var freeDiskGB = 0
    @State private var notificationsDenied = false
    @Environment(SystemStore.self) private var systemStore
    @State private var dns = ContainerDNS.State()
    @State private var dnsDomainField = "test"
    @State private var dnsBusy = false
    @State private var dnsError: PresentedError?
    @State private var helperError: PresentedError?
    @State private var showUninstallConfirmation = false

    var body: some View {
        Form {
            Section {
                if cliPath.isEmpty {
                    LabeledContent("container CLI", value: "Automatic")
                } else {
                    LabeledContent("container CLI") {
                        Text(cliPath)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                HStack {
                    Button("Choose…") { chooseBinary() }
                    Button("Use Automatic") { cliPath = "" }
                        .disabled(cliPath.isEmpty)
                    Spacer()
                    if systemStore.helperStatus == .enabled, systemStore.isInstalledFromPackage {
                        Button("Uninstall container…", role: .destructive) {
                            showUninstallConfirmation = true
                        }
                    }
                }
            } header: {
                Text("Container Tool")
            } footer: {
                Text("Automatic checks the standard install, Homebrew (/opt/homebrew/bin), then the path reported by the running services. Set a path only to override.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Status", value: systemStore.helperStatus.label)
                switch systemStore.helperStatus {
                case .notRegistered:
                    Button("Enable Helper…") {
                        Task { await changeHelper { try PrivilegedHelper.register() } }
                    }
                case .requiresApproval:
                    Button("Open Login Items…") { PrivilegedHelper.openLoginItems() }
                case .enabled:
                    Button("Disable Helper") {
                        Task { await changeHelper { try await PrivilegedHelper.unregister() } }
                    }
                case .unavailable:
                    EmptyView()
                }
                if let helperError {
                    Text(helperError.message)
                        .foregroundStyle(.red)
                        .font(.caption)
                }
            } header: {
                Text("Privileged Helper")
            } footer: {
                Text("Lets Container Manager install, update and remove container, and set up local DNS, without asking for a password each time. macOS asks you to allow it once, in System Settings ▸ General ▸ Login Items & Extensions. Administrators aren't asked again; other accounts need an administrator's password.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Status", value: systemStore.status.label)
                HStack {
                    Button("Restart") {
                        Task { await systemStore.restart() }
                    }
                    .disabled(!(systemStore.isReady || systemStore.status == .baseEnvMissing))
                    if systemStore.status == .starting || systemStore.status == .stopping {
                        ProgressView().controlSize(.small)
                    }
                }
            } header: {
                Text("Services")
            } footer: {
                Text("Restarting stops every running container and machine, then starts the services again. Needed after changing something the services only read at startup, such as the DNS domain below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let health = systemStore.health {
                Section {
                    ServiceDiagnostics(health: health)
                } header: {
                    Text("Diagnostics")
                } footer: {
                    Text("What `container system status` reports. Copy Diagnostics puts it on the clipboard for a bug report.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                dnsRows
            } header: {
                Text("Local DNS")
            } footer: {
                Text(dnsExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Notify me about container activity", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        guard enabled else { return }
                        Task {
                            // Ask only when someone turns it on. If they say no, put the
                            // switch back rather than leaving the app configured to do
                            // something the system won't let it do.
                            if await Notifier.requestAuthorization() {
                                notificationsDenied = false
                            } else {
                                notificationsEnabled = false
                                notificationsDenied = true
                            }
                        }
                    }
                if notificationsDenied {
                    Label(
                        "macOS is blocking notifications for ContainerManager. Allow them in System Settings ▸ Notifications.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.orange)
                    .font(.caption)
                }
                if notificationsEnabled {
                    Toggle("Something stopped unexpectedly", isOn: $notifyStops)
                    Toggle("Long operations finished", isOn: $notifyOperations)
                    Toggle("Resource limits reached", isOn: $notifyThresholds)
                    if notifyThresholds {
                        Picker("Warn at", selection: $cpuThreshold) {
                            Text("Never").tag(0)
                            Text("100% CPU (one core)").tag(100)
                            Text("200% CPU").tag(200)
                            Text("400% CPU").tag(400)
                        }
                        Picker("Warn when free disk is under", selection: $freeDiskGB) {
                            Text("Never").tag(0)
                            Text("5 GB").tag(5)
                            Text("10 GB").tag(10)
                            Text("25 GB").tag(25)
                        }
                    }
                    Picker("Check every", selection: $watchSeconds) {
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                        Text("2 minutes").tag(120)
                    }
                }
            } header: {
                Text("Notifications")
            } footer: {
                Text("Only changes you didn't make are reported — stopping something yourself won't notify you. Checking runs while ContainerManager is open, whether or not a window is showing; with this off, nothing is polled.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Lists") {
                Picker("Refresh every", selection: $refreshSeconds) {
                    Text("2 seconds").tag(2)
                    Text("5 seconds").tag(5)
                    Text("10 seconds").tag(10)
                    Text("30 seconds").tag(30)
                }
            }

            Section {
                Picker("Sample every", selection: $statsSeconds) {
                    Text("1 second").tag(1)
                    Text("2 seconds").tag(2)
                    Text("5 seconds").tag(5)
                    Text("Off").tag(0)
                }
            } header: {
                Text("Statistics")
            } footer: {
                Text("CPU, memory and throughput on the Container and Stack panes. Each container costs one request per sample, and sampling only runs while a pane showing it is open — nothing is measured in the background.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Show menu bar icon", isOn: $showMenuBarIcon)
                    .onChange(of: showMenuBarIcon) { DockIcon.update() }
            } header: {
                Text("Menu Bar")
            } footer: {
                Text("The menu bar icon shows subsystem status and quick access to running machines and stack web UIs. ContainerManager keeps running there after you close the window, and the Dock icon hides until you open a window again.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                component(
                    "ContainerManager", installed: AppUpdater.installedVersion,
                    available: systemStore.availableAppUpdate
                ) {
                    Button("Update…") { systemStore.installAppUpdate() }
                }
                component(
                    "Apple container", installed: systemStore.installedContainerVersion,
                    available: systemStore.availableUpdate
                ) {
                    Button("Update…") {
                        systemStore.promptUpdate()
                        UpdateAlert.presentPending(systemStore)
                    }
                }
                Picker("Check automatically", selection: $updateFrequency) {
                    ForEach(UpdateCheckFrequency.allCases) { frequency in
                        Text(frequency.label).tag(frequency.rawValue)
                    }
                }
                HStack {
                    Button("Check Now") {
                        Task {
                            await systemStore.checkForUpdates(force: true)
                            UpdateAlert.presentPending(systemStore)
                        }
                    }
                    Spacer()
                    Text(lastCheckedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Updates")
            }
        }
        .formStyle(.grouped)
        // Approving the helper happens in System Settings; pick it up on return.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await systemStore.refresh() }
        }
        .confirmationDialog("Uninstall container?", isPresented: $showUninstallConfirmation) {
            Button("Uninstall, Keep Data", role: .destructive) {
                Task { await systemStore.uninstall(deletingData: false) }
            }
            Button("Uninstall and Delete All Data", role: .destructive) {
                Task { await systemStore.uninstall(deletingData: true) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This stops every running container and machine, then removes the container tool and its local DNS entries. Keeping data leaves your images, containers, volumes and machines for a reinstall; deleting it removes them for good.")
        }
        .task { await refreshDNS() }
        .frame(width: 460, height: 600)
    }

    /// A component row: name, installed version, and either an "available" action or an
    /// up-to-date marker.
    @ViewBuilder
    private func component(
        _ name: String, installed: String?, available: String?,
        @ViewBuilder action: () -> some View
    ) -> some View {
        LabeledContent(name) {
            HStack(spacing: 8) {
                Text(installed ?? "—")
                    .foregroundStyle(.secondary)
                if let available {
                    Text("→ \(available)")
                        .foregroundStyle(.green)
                    action()
                }
            }
        }
    }

    private var lastCheckedText: String {
        let date = AppDefaults.lastUpdateCheck
        guard date.timeIntervalSince1970 > 0 else { return "Not checked yet" }
        let formatter = RelativeDateTimeFormatter()
        return "Checked \(formatter.localizedString(for: date, relativeTo: Date()))"
    }

    /// Reflects which of the two halves are in place, since being half set up is the
    /// easy state to land in and the confusing one to be in.
    @ViewBuilder
    private var dnsRows: some View {
        if dns.isActive, let domain = dns.defaultDomain {
            LabeledContent("Domain", value: domain)
            LabeledContent("Containers reachable as", value: "<name>.\(domain)")
            Button("Turn Off") { Task { await turnOffDNS() } }
                .disabled(dnsBusy)
        } else {
            HStack {
                TextField("Domain", text: $dnsDomainField, prompt: Text("test"))
                if dnsBusy {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Set Up…") { Task { await setUpDNS() } }
                        .disabled(!ContainerDNS.isValidDomain(enteredDomain))
                }
            }
            if dns.isIncomplete {
                Label(incompleteDescription, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.caption)
            }
        }
        if let dnsError {
            Text(dnsError.message)
                .foregroundStyle(.red)
                .font(.caption)
        }
    }

    /// DNS names are case-insensitive; resolver files and the helper expect lowercase.
    private var enteredDomain: String {
        dnsDomainField.trimmingCharacters(in: .whitespaces).lowercased()
    }

    private var incompleteDescription: String {
        if dns.defaultDomain == nil, let created = dns.resolverDomains.first {
            return "“\(created)” exists but nothing registers under it yet — set it up to finish."
        }
        if let domain = dns.defaultDomain {
            return "“\(domain)” is set but macOS isn't routing to it — set it up to finish."
        }
        return ""
    }

    private var dnsExplanation: String {
        let base =
            "Makes containers reachable from this Mac by name, so a web UI is at my-app.\(dns.defaultDomain ?? dnsDomainField) rather than an address that changes."
            + (systemStore.helperStatus == .enabled
                ? "" : " Setting it up asks for your administrator password, because macOS needs a resolver entry.")
        let caveats =
            " Containers get the names too, so a stack's services can address each other by name instead of by IP. Both a restart and re-creating a container are needed before it gets one."
        return base + caveats
    }

    private func setUpDNS() async {
        dnsBusy = true
        dnsError = nil
        do {
            let domain = enteredDomain
            if !dns.resolverDomains.contains(domain) {
                try await ContainerDNS.createResolverDomain(domain)
            }
            try ContainerDNS.setDefaultDomain(domain)
            await refreshDNS()
            // The service reads its config once, so the setting does nothing until then.
            if dns.defaultDomain != nil {
                await systemStore.restart()
                await refreshDNS()
            }
        } catch {
            dnsError = PresentedError(title: "Couldn't set up DNS", error: error)
        }
        dnsBusy = false
    }

    private func turnOffDNS() async {
        dnsBusy = true
        dnsError = nil
        do {
            let domain = dns.defaultDomain
            try ContainerDNS.setDefaultDomain(nil)
            // Without the helper the resolver entry stays: it's inert without the config,
            // and removing it would mean another password prompt.
            if let domain {
                try await ContainerDNS.deleteResolverDomain(domain)
            }
            await systemStore.restart()
            await refreshDNS()
        } catch {
            dnsError = PresentedError(title: "Couldn't turn off DNS", error: error)
        }
        dnsBusy = false
    }

    private func refreshDNS() async {
        dns = await ContainerDNS.state()
        if let domain = dns.defaultDomain ?? dns.resolverDomains.first {
            dnsDomainField = domain
        }
    }

    private func changeHelper(_ change: () async throws -> Void) async {
        helperError = nil
        do {
            try await change()
        } catch {
            helperError = PresentedError(title: "Couldn't change the helper", error: error)
        }
        await systemStore.refresh()
    }

    private func chooseBinary() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose the container CLI executable"
        panel.prompt = "Use"
        if panel.runModal() == .OK, let url = panel.url {
            cliPath = url.path
        }
    }
}

/// What `container system status` reports, gathered in-process: the daemon's health
/// ping plus counts from the stores, so they match the lists.
private struct ServiceDiagnostics: View {
    let health: SystemHealth
    @Environment(ContainersStore.self) private var containersStore
    @Environment(ImagesStore.self) private var imagesStore

    private var serviceVersion: String {
        ContainerVersion.parse(health.apiServerVersion).map { "\($0.0).\($0.1).\($0.2)" }
            ?? health.apiServerVersion
    }

    private var versionsDiffer: Bool {
        guard let service = ContainerVersion.parse(health.apiServerVersion),
            let linked = ContainerVersion.parse(ContainerVersion.linkedLibrary)
        else { return false }
        return service != linked
    }

    /// "macOS 27.0 (26A428) · 10 CPUs", from "Version 27.0 (Build 26A428)".
    private var host: String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString
            .replacingOccurrences(of: "Version ", with: "macOS ")
            .replacingOccurrences(of: "Build ", with: "")
        return "\(os) · \(ProcessInfo.processInfo.processorCount) CPUs"
    }

    private var runningCount: Int {
        containersStore.containers.filter { $0.status == .running }.count
    }

    private var paths: [(label: String, path: String)] {
        var paths = [
            ("App root", health.appRoot.path(percentEncoded: false)),
            ("Install root", health.installRoot.path(percentEncoded: false)),
        ]
        if let logRoot = health.logRoot {
            paths.append(("Log root", String(describing: logRoot)))
        }
        return paths
    }

    var body: some View {
        LabeledContent("Services", value: "\(serviceVersion) (\(health.apiServerBuild))")
        LabeledContent("Commit") {
            Text(health.apiServerCommit)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
        LabeledContent("Client libraries", value: ContainerVersion.linkedLibrary)
        if versionsDiffer {
            Label(
                "The services and ContainerManager's client libraries differ. Update whichever is older so they match.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .foregroundStyle(.orange)
            .font(.caption)
        }
        LabeledContent("Host", value: host)
        ForEach(paths, id: \.label) { entry in
            // An HStack rather than LabeledContent, which moves a long value onto a line
            // of its own instead of truncating it.
            HStack(spacing: 4) {
                Text(entry.label)
                Spacer(minLength: 16)
                Text((entry.path as NSString).abbreviatingWithTildeInPath)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(entry.path)
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: entry.path)])
                } label: {
                    Image(systemName: "arrow.forward.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Show in Finder")
            }
        }
        LabeledContent("Containers", value: "\(runningCount) running of \(containersStore.containers.count)")
        LabeledContent("Images", value: "\(imagesStore.images.count)")
        Button("Copy Diagnostics") { Pasteboard.copy(diagnostics) }
            .task {
                await containersStore.refresh()
                await imagesStore.refresh()
            }
    }

    private var diagnostics: [String] {
        [
            "ContainerManager: \(AppUpdater.installedVersion)",
            "Client libraries: \(ContainerVersion.linkedLibrary)",
            "Services: \(serviceVersion) (\(health.apiServerBuild))",
            "Services commit: \(health.apiServerCommit)",
            "Host: \(host)",
        ]
            + paths.map { "\($0.label): \($0.path)" }
            + [
                "Containers: \(runningCount) running of \(containersStore.containers.count)",
                "Images: \(imagesStore.images.count)",
            ]
    }
}
