//
//  CLIPathResolver.swift
//  ContainerManager
//

import ContainerAPIClient
import Foundation

/// Resolves the path to the `container` CLI that matches the running daemons.
enum CLIPathResolver {
    /// Explicit user override (e.g. for development builds).
    static let overrideKey = "containerBinaryPath"
    /// Derived from the daemon's installRoot the last time a health ping succeeded.
    static let lastKnownGoodKey = "lastKnownContainerBinaryPath"

    static let standardPath = "/usr/local/bin/container"

    /// Resolution order: user override → standard install → last known good
    /// (from the daemon's reported installRoot). Nil when none is executable.
    static var effectivePath: String? {
        let candidates = [
            UserDefaults.standard.string(forKey: overrideKey),
            standardPath,
            UserDefaults.standard.string(forKey: lastKnownGoodKey),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// Records the CLI location reported by a live daemon so the app can start
    /// services again later even when the daemon is stopped.
    static func observe(health: SystemHealth) {
        let path = health.installRoot
            .appendingPathComponent("bin")
            .appendingPathComponent("container")
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        UserDefaults.standard.set(path, forKey: lastKnownGoodKey)
    }
}
