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
    /// Raised to 1.2.0 when the app moved to the 1.2.1 client libraries: 1.2.0 is the
    /// oldest daemon that combination has actually been verified against, and
    /// `container export` for live containers needs 1.2.1. Older daemons would fail
    /// obscurely over XPC rather than being told to update.
    static let minimum = (1, 2, 0)
    static let minimumString = "1.2.0"

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

    /// True when `latest` is a higher version than `current`. False if either is unparseable.
    static func isUpdate(latest: String, over current: String) -> Bool {
        guard let l = parse(latest), let c = parse(current) else { return false }
        return l > c
    }
}
