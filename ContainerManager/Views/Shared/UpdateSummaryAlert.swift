//
//  UpdateSummaryAlert.swift
//  ContainerManager
//

import SwiftUI

/// What an update check found, in the form the interface needs to present it.
///
/// The versions are the *actions* available, not just text: a container update is
/// applied in place, while the app is downloaded from its release page.
struct UpdateSummary: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    /// Newer container version, when one can be installed.
    let container: String?
    /// Newer ContainerManager version, when one can be downloaded.
    let app: String?

    var hasUpdate: Bool { container != nil || app != nil }
}

extension View {
    /// Presents the pending update summary, if any.
    ///
    /// Attached to both the main window and Settings, since a check can be started from
    /// either. With both windows open they present together — but they share one value,
    /// so answering either clears it and both close. An earlier attempt to show it only
    /// in the key window, via `controlActiveState`, stopped it appearing at all.
    func updateSummaryAlert(_ store: SystemStore) -> some View {
        modifier(UpdateSummaryAlert(store: store))
    }
}

private struct UpdateSummaryAlert: ViewModifier {
    let store: SystemStore

    func body(content: Content) -> some View {
        content.alert(
            store.updateSummary?.title ?? "Software Update",
            isPresented: Binding(
                get: { store.updateSummary != nil },
                set: { if !$0 { store.updateSummary = nil } }
            ),
            presenting: store.updateSummary
        ) { summary in
            // Buttons are declared by what they do, rather than the old approach of
            // adding them in order and matching a response index back to an action.
            if summary.container != nil {
                Button("Update container…") {
                    Task { await store.applyUpdate() }
                }
            }
            if summary.app != nil {
                Button("Get ContainerManager…") { store.openAppReleasePage() }
            }
            Button(summary.hasUpdate ? "Later" : "OK", role: .cancel) {}
        } message: { summary in
            Text(summary.message)
        }
    }
}
