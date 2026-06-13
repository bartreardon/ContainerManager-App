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
    static let minimum = (1, 0, 0)
    static let minimumString = "1.0.0"

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
}
