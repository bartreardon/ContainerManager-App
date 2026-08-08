//
//  SettingsView.swift
//  ContainerManager
//

import AppKit
import SwiftUI

/// App preferences (⌘,). Keys are shared with the rest of the app via `@AppStorage`:
/// `containerBinaryPath` is read by `CLIPathResolver`; `listRefreshSeconds` by the lists.
struct SettingsView: View {
    @AppStorage("containerBinaryPath") private var cliPath = ""
    @AppStorage("listRefreshSeconds") private var refreshSeconds = 5
    @AppStorage(AppDefaults.updateCheckFrequencyKey) private var updateFrequency = UpdateCheckFrequency.weekly.rawValue
    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @Environment(SystemStore.self) private var systemStore

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
                }
            } header: {
                Text("Container Tool")
            } footer: {
                Text("Automatic checks the standard install, Homebrew (/opt/homebrew/bin), then the path reported by the running services. Set a path only to override.")
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
                    "ContainerManager", installed: AppUpdateChecker.installedVersion,
                    available: systemStore.availableAppUpdate
                ) {
                    Button("Get Update…") { systemStore.openAppReleasePage() }
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
        .frame(width: 460, height: 520)
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
