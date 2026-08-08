//
//  UpdateAlert.swift
//  ContainerManager
//

import AppKit

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

/// Presents the update summary the store has prepared.
///
/// App-modal on purpose. A SwiftUI `.alert` belongs to a window, but an available
/// update belongs to the app: bound to shared state it appeared in *every* open window
/// at once, and attaching it to Settings made SwiftUI summon that window in order to
/// present it. This shows one alert, from wherever the check was started, whether or
/// not a window is open.
///
/// The store still decides what there is to say — it holds no AppKit and runs nothing
/// modal itself.
enum UpdateAlert {
    /// A button and what it does, kept together so the two can't drift apart. The old
    /// version added buttons in one order and matched the response back by incrementing
    /// an index, which had to be re-derived by hand whenever a button was added.
    struct Choice {
        let title: String
        let action: () -> Void
    }

    /// The choices for `summary`, in the order they're shown.
    static func choices(for summary: UpdateSummary, store: SystemStore) -> [Choice] {
        var choices: [Choice] = []
        if summary.container != nil {
            choices.append(Choice(title: "Update container…") { Task { await store.applyUpdate() } })
        }
        if summary.app != nil {
            choices.append(Choice(title: "Get ContainerManager…") { store.openAppReleasePage() })
        }
        // Trailing button: nothing to do either way, but it shouldn't say "Later" when
        // there's nothing to be later about.
        choices.append(Choice(title: summary.hasUpdate ? "Later" : "OK") {})
        return choices
    }

    /// Presents any summary the store is holding, and runs the chosen action.
    static func presentPending(_ store: SystemStore) {
        guard let summary = store.updateSummary else { return }
        store.updateSummary = nil

        let choices = choices(for: summary, store: store)
        let alert = NSAlert()
        alert.messageText = summary.title
        alert.informativeText = summary.message
        for choice in choices {
            alert.addButton(withTitle: choice.title)
        }

        let index = alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        guard choices.indices.contains(index) else { return }
        choices[index].action()
    }
}
