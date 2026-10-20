//
//  ContainerVersionTests.swift
//  ContainerManagerTests
//

import Testing

@testable import ContainerManager

/// The daemon reported `container-apiserver version 1.2.1 (…)` up to 1.2.x and a bare
/// `1.4.1` from 1.4.1, while the CLI still says `container CLI version …`. All three
/// must parse, or a current install reads as outdated and the app gates itself off.
@Suite("ContainerVersion")
struct ContainerVersionTests {
    @Test("Parses every shape the daemon and CLI report", arguments: [
        ("1.4.1", 1, 4, 1),
        ("container-apiserver version 1.2.1 (build: release, commit: 0d111be)", 1, 2, 1),
        ("container CLI version 1.4.1 (build: release, commit: 9a8917c)", 1, 4, 1),
        ("container CLI version 1.0.0-4-gc8b4fd7 (build: release …)", 1, 0, 0),
    ])
    func parses(raw: String, major: Int, minor: Int, patch: Int) {
        let parsed = ContainerVersion.parse(raw)
        #expect(parsed?.0 == major && parsed?.1 == minor && parsed?.2 == patch)
    }

    @Test("Unparseable strings don't meet the minimum")
    func unparseable() {
        #expect(ContainerVersion.parse("unspecified") == nil)
        #expect(!ContainerVersion.meetsMinimum("unspecified"))
    }

    @Test("Older releases are outdated, newer ones pass", arguments: [
        ("1.4.1", false), ("1.4.9", false), ("1.5.0", true), ("1.6.0", true), ("1.6.1", true), ("2.0.0", true),
    ])
    func minimum(version: String, meets: Bool) {
        #expect(ContainerVersion.meetsMinimum(version) == meets)
    }

    @Test("Feature gates compare against the services' version", arguments: [
        ("1.5.0", false), ("container-apiserver version 1.5.0 (build: release)", false),
        ("1.6.0", true), ("1.7.2", true), ("unspecified", false),
    ])
    func atLeast(version: String, supported: Bool) {
        #expect(ContainerVersion.atLeast(ContainerVersion.machineHome, version) == supported)
    }
}
