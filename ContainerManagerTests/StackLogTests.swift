//
//  StackLogTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// `append` used to read the whole file and write it back; it now seeks to the end.
/// That's two code paths — creating the file and extending it — and getting the second
/// wrong would truncate the record of how a stack was built.
@Suite("StackLog")
struct StackLogTests {
    /// A name no real stack will have, cleaned up afterwards.
    private func withScratchLog(_ body: (String) throws -> Void) rethrows {
        let name = "containermanager-test-\(UUID().uuidString)"
        defer { StackLog.delete(for: name) }
        try body(name)
    }

    @Test("Appending twice keeps both entries, in order")
    func appendsAccumulate() throws {
        try withScratchLog { name in
            #expect(StackLog.exists(for: name) == false)

            StackLog.append(section: "First", lines: ["alpha"], to: name)
            StackLog.append(section: "Second", lines: ["beta"], to: name)

            let text = StackLog.read(for: name)
            #expect(text.contains("First"))
            #expect(text.contains("alpha"))
            #expect(text.contains("Second"))
            #expect(text.contains("beta"))
            // The whole point: the second write extends rather than replaces.
            let first = try #require(text.range(of: "First"))
            let second = try #require(text.range(of: "Second"))
            #expect(first.lowerBound < second.lowerBound)
        }
    }

    @Test("Many appends all survive")
    func manyAppends() {
        withScratchLog { name in
            for index in 0..<50 {
                StackLog.append(section: "Step \(index)", lines: ["line \(index)"], to: name)
            }
            let text = StackLog.read(for: name)
            #expect(text.contains("line 0"))
            #expect(text.contains("line 49"))
            #expect(text.components(separatedBy: "=====").count == 101)  // 2 markers per entry
        }
    }

    @Test("An empty section writes nothing at all")
    func emptySectionsAreSkipped() {
        withScratchLog { name in
            StackLog.append(section: "Nothing", lines: [], to: name)
            StackLog.append(section: "Blank", lines: ["", "   "], to: name)
            #expect(StackLog.exists(for: name) == false)
        }
    }

    @Test("The log is created readable only by its owner")
    func permissionsOnCreate() throws {
        try withScratchLog { name in
            StackLog.append(section: "First", lines: ["alpha"], to: name)
            let url = try StackLog.url(for: name)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
            #expect(permissions.int16Value == 0o600)
        }
    }

    @Test("Deleting removes the file")
    func deleteRemoves() {
        withScratchLog { name in
            StackLog.append(section: "First", lines: ["alpha"], to: name)
            #expect(StackLog.exists(for: name))
            StackLog.delete(for: name)
            #expect(StackLog.exists(for: name) == false)
            #expect(StackLog.read(for: name).isEmpty)
        }
    }
}
