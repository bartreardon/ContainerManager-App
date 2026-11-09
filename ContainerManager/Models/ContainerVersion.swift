//
//  ContainerVersion.swift
//  ContainerManager
//

import Foundation

/// Parses and compares `container` version strings such as
/// "container CLI version 1.0.0-4-gc8b4fd7 (build: release …)" or
/// "container-apiserver version 1.0.0 (…)".
enum ContainerVersion {
    /// The minimum container version ContainerManager supports.
    ///
    /// Older daemons fail obscurely over XPC rather than being told to update. The 1.7
    /// client libraries ask the services for an image's platforms before creating a
    /// container, a route that first shipped in 1.6.1. Features newer than the minimum
    /// check `atLeast` against the services.
    static let minimum = (1, 6, 1)
    static let minimumString = "1.6.1"

    /// The apple/container package version the app is built against. Keep in step with
    /// the exact-version pin in project.pbxproj.
    static let linkedLibrary = "1.7.1"

    /// Extracts the first `major.minor.patch` triple found in the string.
    static func parse(_ string: String) -> (Int, Int, Int)? {
        guard
            let match = string.firstMatch(of: /(\d+)\.(\d+)\.(\d+)/),
            let major = Int(match.1), let minor = Int(match.2), let patch = Int(match.3)
        else {
            return nil
        }
        return (major, minor, patch)
    }

    /// Returns true if the version in `string` is at least `minimum`.
    static func meetsMinimum(_ string: String) -> Bool {
        guard let v = parse(string) else { return false }
        return v >= minimum
    }

    /// True when the version in `string` is at least `version`. False if unparseable.
    static func atLeast(_ version: (Int, Int, Int), _ string: String) -> Bool {
        guard let v = parse(string) else { return false }
        return v >= version
    }

    /// True when `latest` is a higher version than `current`. False if either is unparseable.
    static func isUpdate(latest: String, over current: String) -> Bool {
        guard let l = parse(latest), let c = parse(current) else { return false }
        return l > c
    }
}
