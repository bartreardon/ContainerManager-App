//
//  MenuBarView.swift
//  ContainerManager
//

import AppKit
import ContainerResource
import MachineAPIClient
import SwiftUI

/// The menu bar icon. Reflects subsystem status and hosts the background refresh loop
/// that keeps the icon and menu current even with no app window open (the label view
/// stays instantiated for the life of the menu bar item).
struct MenuBarLabel: View {
    @Environment(SystemStore.self) private var systemStore
    @Environment(MachinesStore.self) private var machinesStore
    @Environment(StacksStore.self) private var stacksStore

    var body: some View {
        Image(systemName: systemStore.status.menuBarSymbol)
            .accessibilityLabel("ContainerManager — \(systemStore.status.label)")
            .task { await pollLoop() }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await systemStore.refresh()
            // Machine/stack clients only work once the subsystem is ready; skip them
            // otherwise so a stopped daemon doesn't raise errors.
            if systemStore.isReady {
                await machinesStore.refresh()
                await stacksStore.refresh()
            }
            try? await Task.sleep(for: AppDefaults.listRefresh)
        }
    }
}

/// The dropdown shown from the menu bar icon: subsystem status + start/stop, running
/// machines, and stack web UIs, plus show-window and quit.
struct MenuBarView: View {
    @Environment(SystemStore.self) private var systemStore
    @Environment(MachinesStore.self) private var machinesStore
    @Environment(StacksStore.self) private var stacksStore
    @Environment(\.openWindow) private var openWindow

    private var runningMachines: [MachineSnapshot] {
        machinesStore.machines.filter { $0.status == .running }
    }

    private var webStacks: [Stack] {
        stacksStore.stacks.filter { $0.webURL != nil }
    }

    var body: some View {
        Text("Container services: \(systemStore.status.label)")

        switch systemStore.status {
        case .stopped, .unknown:
            Button("Start Services") { Task { await systemStore.start() } }
                .disabled(systemStore.status == .unknown)
        case .running, .baseEnvMissing:
            Button("Stop Services") { Task { await systemStore.stop() } }
        default:
            EmptyView()
        }

        Divider()

        if runningMachines.isEmpty {
            Text("No running machines")
        } else {
            ForEach(runningMachines, id: \.id) { machine in
                Menu(machine.id) {
                    Button("Open Terminal") {
                        Task { _ = await TerminalLauncher.openMachineShell(machineId: machine.id) }
                    }
                    if let ip = machine.ipAddress {
                        Button("Copy IP (\(ip))") { Pasteboard.copy([ip]) }
                    }
                }
            }
        }

        if !webStacks.isEmpty {
            Divider()
            Text("Web UIs")
            ForEach(webStacks) { stack in
                // Running → open the URL; not running → start the stack (the URL
                // wouldn't resolve yet).
                if stack.allRunning, let url = stack.webURL {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open \(stack.displayName)", systemImage: stack.icon)
                    }
                } else {
                    Button {
                        Task { await stacksStore.start(name: stack.name) }
                    } label: {
                        Label("Start \(stack.displayName)", systemImage: stack.icon)
                    }
                }
            }
        }

        Divider()

        Button("Open Container Manager") {
            // Return to a regular app first so a window from an accessory state comes
            // forward reliably; the window observers keep the policy in sync after.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            // Reuse an existing window; only make one if none are open.
            if !AppWindows.hasOrdinaryVisible { openWindow(id: "main") }
        }
        Button("Quit ContainerManager") { NSApplication.shared.terminate(nil) }
    }
}
