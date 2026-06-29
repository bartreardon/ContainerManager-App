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
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 240)
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
