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
    /// Homebrew on Apple silicon installs to /opt/homebrew/bin.
    static let homebrewPath = "/opt/homebrew/bin/container"

    /// Resolution order: user override → standard install (official installer) →
    /// Homebrew location → last known good (from the daemon's reported installRoot).
    /// Nil when none is executable.
    static var effectivePath: String? {
        let candidates = [
            UserDefaults.standard.string(forKey: overrideKey),
            standardPath,
            homebrewPath,
            UserDefaults.standard.string(forKey: lastKnownGoodKey),
        ]
        return candidates.compactMap { $0 }.first {
            FileManager.default.isExecutableFile(atPath: $0)
        }
    }

    /// Records the CLI location reported by a live daemon so the app can start
    /// services again later even when the daemon is stopped.
    ///
    /// This covers installs in non-standard locations (e.g. a custom prefix) once
    /// the daemon has run — but only *after* a successful health ping, so it can't
    /// be the sole mechanism. The static candidates in `effectivePath` (including
    /// the Homebrew path) handle cold start, before any ping has happened.
    static func observe(health: SystemHealth) {
        let path = health.installRoot
            .appendingPathComponent("bin")
            .appendingPathComponent("container")
            .path
        guard FileManager.default.isExecutableFile(atPath: path) else { return }
        UserDefaults.standard.set(path, forKey: lastKnownGoodKey)
    }
}
