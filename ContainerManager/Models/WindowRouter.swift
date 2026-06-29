//
//  WindowRouter.swift
//  ContainerManager
//

import Foundation
import Observation
import SwiftUI

/// Per-window navigation + intent state. Lives in `RootView` and is exposed to the
/// menu bar via `focusedSceneValue` so File/View commands act on the focused window.
/// Context menus and the sidebar also drive creation/terminal intents through it.
@Observable
final class WindowRouter {
    var section: SidebarSection = .machines

    var selectedStackName: String?
    var selectedMachineId: String?
    var selectedContainerId: String?
    var selectedImageReference: String?
    var selectedNetworkId: String?
    var selectedVolumeName: String?

    /// Set to request that the matching list view present its create sheet.
    var pendingCreate: SidebarSection?
    /// Set (with the section switched + item selected) to ask a detail view to open
    /// its in-app Terminal tab for this id.
    var openTerminalForId: String?

    func select(_ section: SidebarSection) {
        self.section = section
    }

    func requestCreate(_ section: SidebarSection) {
        self.section = section
        pendingCreate = section
    }

    /// Switch to `section`, select `id`, and ask its detail view to open the terminal.
    func openTerminal(id: String, in section: SidebarSection) {
        self.section = section
        switch section {
        case .machines: selectedMachineId = id
        case .containers: selectedContainerId = id
        default: break
        }
        openTerminalForId = id
    }
}

// MARK: - Focused value plumbing for menu commands

struct WindowRouterFocusedKey: FocusedValueKey {
    typealias Value = WindowRouter
}

extension FocusedValues {
    var windowRouter: WindowRouter? {
        get { self[WindowRouterFocusedKey.self] }
        set { self[WindowRouterFocusedKey.self] = newValue }
    }
}
