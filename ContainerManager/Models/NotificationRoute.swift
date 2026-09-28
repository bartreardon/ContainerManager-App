//
//  NotificationRoute.swift
//  ContainerManager
//

import Foundation

/// Where a tapped notification wants the app to go.
///
/// Shared rather than injected because the app delegate receives the tap, and it has no
/// window — and therefore no `WindowRouter` — to hand it to. A window picks this up when
/// one exists, the same way `WindowRouter.pendingStackImport` is consumed by the stacks
/// list after a file is opened from Finder.
@Observable
@MainActor
final class NotificationRoute {
    static let shared = NotificationRoute()

    struct Destination: Equatable {
        let section: SidebarSection
        let item: String?
    }

    /// Cleared by whichever window takes it, so a second window doesn't jump too.
    var pending: Destination?

    private init() {}
}
