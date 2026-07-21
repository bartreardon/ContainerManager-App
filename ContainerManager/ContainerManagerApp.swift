//
//  ContainerManagerApp.swift
//  ContainerManager
//
//  Created by Bart E Reardon on 12/6/2026.
//

import AppKit
import SwiftUI

@main
struct ContainerManagerApp: App {
    @State private var systemStore = SystemStore()
    @State private var machinesStore = MachinesStore()
    @State private var containersStore = ContainersStore()
    @State private var imagesStore = ImagesStore()
    @State private var networksStore = NetworksStore()
    @State private var volumesStore = VolumesStore()
    @State private var stacksStore = StacksStore()
    @State private var imageImportModel = ImageImportModel()

    @AppStorage("showMenuBarIcon") private var showMenuBarIcon = true
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(systemStore)
                .environment(machinesStore)
                .environment(containersStore)
                .environment(imagesStore)
                .environment(networksStore)
                .environment(volumesStore)
                .environment(stacksStore)
                .environment(imageImportModel)
        }
        .commands {
            AppCommands(systemStore: systemStore)
        }

        Settings {
            SettingsView()
                .environment(systemStore)
        }

        MenuBarExtra(isInserted: $showMenuBarIcon) {
            MenuBarView()
                .environment(systemStore)
                .environment(machinesStore)
                .environment(stacksStore)
        } label: {
            MenuBarLabel()
                .environment(systemStore)
                .environment(machinesStore)
                .environment(stacksStore)
        }
        .menuBarExtraStyle(.menu)
    }
}

/// Keeps the Dock icon in sync with window presence: shown while an ordinary window
/// is open, hidden (menu-bar only) once the last one closes. Runs from an app delegate
/// because `NSApp` isn't available during `App.init`.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let center = NotificationCenter.default
        for name: Notification.Name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            center.addObserver(self, selector: #selector(windowsChanged), name: name, object: nil)
        }
        DockIcon.update()
    }

    // On close the window is still counted synchronously, so re-evaluate next runloop.
    @objc private func windowsChanged() {
        DispatchQueue.main.async { DockIcon.update() }
    }
}

/// Titled, non-panel windows — the main window and Settings, not menus/popovers.
enum AppWindows {
    static var hasOrdinaryVisible: Bool {
        NSApp.windows.contains {
            $0.isVisible && $0.styleMask.contains(.titled) && !($0 is NSPanel)
        }
    }
}

/// Switches the app's activation policy so the Dock icon tracks window presence.
/// Not sandboxed, so this is permitted. Stays `.regular` when the menu bar icon is
/// off, so the app always has at least one way to reach it.
enum DockIcon {
    static func update() {
        let menuBarShown = UserDefaults.standard.object(forKey: "showMenuBarIcon") as? Bool ?? true
        let hide = !AppWindows.hasOrdinaryVisible && menuBarShown
        NSApplication.shared.setActivationPolicy(hide ? .accessory : .regular)
    }
}
