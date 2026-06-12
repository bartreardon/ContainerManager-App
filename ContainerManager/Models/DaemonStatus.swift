//
//  DaemonStatus.swift
//  ContainerManager
//

import Foundation

/// State of the `container` system services on this Mac.
enum DaemonStatus: Equatable {
    case unknown
    case notInstalled
    case stopped
    case starting
    case stopping
    case running
}
