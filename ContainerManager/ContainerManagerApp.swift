//
//  ContainerManagerApp.swift
//  ContainerManager
//
//  Created by Bart E Reardon on 12/6/2026.
//

import AppKit
import SwiftUI
import UserNotifications

@main
struct ContainerManagerApp: App {
    @State private var systemStore: SystemStore
    @State private var machinesStore: MachinesStore
    @State private var containersStore: ContainersStore
    @State private var imagesStore = ImagesStore()
    @State private var networksStore = NetworksStore()
    @State private var volumesStore = VolumesStore()
    @State private var stacksStore: StacksStore
    @State private var statsStore: StatsStore
    @State private var imageImportModel = ImageImportModel()
    /// Held for the app's lifetime, not a scene's: it exists to notice things while no
    /// window is open, so it can't be started from a view.
    @State private var watcher: ActivityWatcher

    init() {
        let system = SystemStore()
        let machines = MachinesStore()
        let containers = ContainersStore()
        let stacks = StacksStore()
        let stats = StatsStore()
        _systemStore = State(initialValue: system)
        _machinesStore = State(initialValue: machines)
        _containersStore = State(initialValue: containers)
        _stacksStore = State(initialValue: stacks)
        _statsStore = State(initialValue: stats)
        _watcher = State(
            initialValue: ActivityWatcher(
                system: system, containers: containers, machines: machines, stacks: stacks,
                stats: stats))
    }

    @AppStorage(AppDefaults.showMenuBarIconKey) private var showMenuBarIcon = true
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
                .environment(statsStore)
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
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Taps arrive here, which is why routing goes through the shared route rather
        // than a window's own router — at this point there may be no window at all.
        UNUserNotificationCenter.current().delegate = self
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

    /// A notification was tapped: come forward, and remember where to go.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        let info = response.notification.request.content.userInfo
        if let raw = info[Notifier.sectionKey] as? String,
            let section = SidebarSection(rawValue: raw)
        {
            NotificationRoute.shared.pending = .init(
                section: section, item: info[Notifier.itemKey] as? String)
        }
        // Same dance as the menu bar's "Open Container Manager": become a regular app
        // first, or a window won't come forward from the accessory state.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if !AppWindows.hasOrdinaryVisible {
            NSApp.sendAction(#selector(NSApplication.newWindowForTab(_:)), to: nil, from: nil)
        }
    }

    /// Show banners even when ContainerManager is frontmost. The watcher only reports
    /// things you didn't do, so it's still news while the app is open.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
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
        let menuBarShown = AppDefaults.showMenuBarIcon
        let hide = !AppWindows.hasOrdinaryVisible && menuBarShown
        NSApplication.shared.setActivationPolicy(hide ? .accessory : .regular)
    }
}
