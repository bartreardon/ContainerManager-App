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
    /// Older daemons fail obscurely over XPC rather than being told to update. The 1.6
    /// client libraries still work with 1.5 services, which matters while 1.6.0 has no
    /// signed installer; features that need 1.6 check `atLeast` against the services.
    static let minimum = (1, 5, 0)
    static let minimumString = "1.5.0"

    /// The apple/container package version the app is built against. Keep in step with
    /// the exact-version pin in project.pbxproj.
    static let linkedLibrary = "1.6.0"

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

    /// Services version that keeps a custom home folder for a machine's account. 1.5
    /// accepts the account but re-derives /home/<user>.
    static let machineHome = (1, 6, 0)

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
