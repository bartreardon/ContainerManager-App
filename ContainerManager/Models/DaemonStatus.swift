//
//  DaemonStatus.swift
//  ContainerManager
//

import SwiftUI

/// State of the `container` system services on this Mac.
enum DaemonStatus: Equatable {
    case unknown
    /// The container CLI/daemon isn't installed.
    case notInstalled
    /// Downloading/installing (or updating) the container tool.
    case installing
    /// Installed, but older than the minimum version the app supports.
    case outdated(String)
    case stopped
    case starting
    case stopping
    /// Services running and the base Linux environment is present — ready to use.
    case running
    /// Services running, but the kernel and/or base init filesystem aren't installed.
    case baseEnvMissing
}

// MARK: - Presentation

extension DaemonStatus {
    /// Short human-readable status, e.g. for the sidebar footer and menu bar.
    var label: String {
        switch self {
        case .running: "Running"
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case .installing: "Installing…"
        case .stopped: "Stopped"
        case .notInstalled: "Not installed"
        case .outdated: "Update required"
        case .baseEnvMissing: "Setup incomplete"
        case .unknown: "Checking…"
        }
    }

    /// Colour for the status indicator dot.
    var tint: Color {
        switch self {
        case .running: .green
        case .starting, .stopping, .installing: .orange
        case .outdated, .baseEnvMissing: .yellow
        case .stopped, .notInstalled, .unknown: .secondary.opacity(0.5)
        }
    }

    /// SF Symbol for the menu bar icon — filled while the subsystem is up, outline
    /// otherwise, so state reads without relying on colour (the menu bar is monochrome).
    var menuBarSymbol: String {
        switch self {
        case .running: "shippingbox.fill"
        case .baseEnvMissing, .outdated: "shippingbox.badge.gearshape"
        default: "shippingbox"
        }
    }

    /// A transient state where an action is already in flight.
    var isTransitional: Bool {
        switch self {
        case .starting, .stopping, .installing: true
        default: false
        }
    }
}
