//
//  DaemonStatus.swift
//  ContainerManager
//

import Foundation

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
