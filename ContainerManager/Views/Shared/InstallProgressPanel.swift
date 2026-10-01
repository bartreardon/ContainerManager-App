//
//  InstallProgressPanel.swift
//  ContainerManager
//

import AppKit
import Observation
import SwiftUI

/// A small window showing what an install, update or uninstall of container is doing,
/// for as long as `SystemStore.installProgress` is set.
///
/// Owned by the app rather than a window, for the same reason as `UpdateAlert`: an
/// update can be started from the menu bar with no window open, and the work belongs to
/// the app. It's an ordinary-level panel, not a floating one, so it doesn't sit over
/// Installer.app or anything else the user switches to.
@MainActor
final class InstallProgressPanel {
    private let store: SystemStore
    private var panel: NSPanel?

    init(store: SystemStore) {
        self.store = store
        observe()
    }

    /// Shows or hides the panel as progress starts and stops, re-arming after each
    /// change. Step changes within one run are picked up by the SwiftUI view itself.
    private func observe() {
        let active = withObservationTracking {
            store.installProgress != nil
        } onChange: { [weak self] in
            Task { @MainActor in self?.observe() }
        }
        if active { show() } else { hide() }
    }

    private func show() {
        guard panel == nil else { return }
        let hosting = NSHostingView(rootView: InstallProgressView(store: store))
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: hosting.fittingSize),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered, defer: false)
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = hosting
        panel.center()
        self.panel = panel
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        panel?.close()
        panel = nil
    }
}

private struct InstallProgressView: View {
    let store: SystemStore

    var body: some View {
        let progress = store.installProgress
        VStack(alignment: .leading, spacing: 10) {
            Text(progress?.title ?? "")
                .font(.headline)
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView()
                    .progressViewStyle(.linear)
            }
            Text(progress?.step ?? "")
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(2, reservesSpace: true)
        }
        .padding(20)
        .frame(width: 340)
    }
}
