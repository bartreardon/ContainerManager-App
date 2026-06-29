//
//  AppCommands.swift
//  ContainerManager
//

import AppKit
import SwiftUI

/// Menu bar commands. Per-window actions (New ▸, View ▸) target the focused
/// window via `@FocusedValue(\.windowRouter)`; system start/stop acts on the
/// app-wide `SystemStore`.
struct AppCommands: Commands {
    let systemStore: SystemStore
    @FocusedValue(\.windowRouter) private var router

    private static let createSections: [SidebarSection] = [
        .machines, .containers, .stacks, .images, .networks, .volumes,
    ]

    private func shortcut(for section: SidebarSection) -> KeyEquivalent? {
        switch section {
        case .machines: "m"
        case .containers: "k"
        case .stacks: "s"
        case .images: "b"
        default: nil
        }
    }

    var body: some Commands {
        // File ▸ New ▸ …  (added alongside the default "New Window")
        CommandGroup(after: .newItem) {
            Menu("New") {
                ForEach(Self.createSections) { section in
                    let button = Button(section.singularName) { router?.requestCreate(section) }
                    if let key = shortcut(for: section) {
                        button.keyboardShortcut(key, modifiers: [.command, .shift])
                    } else {
                        button
                    }
                }
            }
            .disabled(router == nil)

            Button("New Tab") { openNewTab() }
                .keyboardShortcut("t", modifiers: .command)
        }

        // File ▸ container services
        CommandGroup(after: .saveItem) {
            Divider()
            Button("Start Container Services") {
                Task { await systemStore.start() }
            }
            .disabled(!(systemStore.status == .stopped || systemStore.status == .unknown))
            Button("Stop Container Services") {
                Task { await systemStore.stop() }
            }
            .disabled(!(systemStore.status == .running || systemStore.status == .baseEnvMissing))
        }

        // View menu ▸ section switching (⌘1–⌘6, matching sidebar order),
        // added to the existing View menu next to the sidebar toggle.
        CommandGroup(after: .sidebar) {
            Divider()
            ForEach(Array(SidebarSection.allCases.enumerated()), id: \.element) { index, section in
                Button(section.rawValue) { router?.select(section) }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                    .disabled(router == nil)
            }
        }

        // Help ▸ replace the useless default with useful links
        CommandGroup(replacing: .help) {
            Link("ContainerManager on GitHub", destination: URL(string: "https://github.com/bartreardon/ContainerManager-App")!)
            Divider()
            Link("Container Machines Guide", destination: docURL("container-machine.md"))
            Link("Stacks Guide", destination: docURL("stacks.md"))
            Link("Building Images Guide", destination: docURL("building-images.md"))
        }
    }

    private func docURL(_ file: String) -> URL {
        URL(string: "https://github.com/bartreardon/ContainerManager-App/blob/main/docs/\(file)")!
    }

    /// Opens a new window as a tab of the current one (⌘T), keeping ⌘N = New Window.
    private func openNewTab() {
        guard let currentWindow = NSApp.keyWindow,
            let windowController = currentWindow.windowController
        else { return }
        windowController.newWindowForTab(nil)
        if let newWindow = NSApp.keyWindow, currentWindow != newWindow {
            currentWindow.addTabbedWindow(newWindow, ordered: .above)
        }
    }
}
