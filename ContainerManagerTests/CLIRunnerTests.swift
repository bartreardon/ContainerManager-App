//
//  CLIRunnerTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// Cancellation is the point of these: a `container build` runs for minutes, and
/// before this it could not be stopped at all. They use `/bin/sleep` rather than the
/// real CLI so they prove the mechanism without needing container installed.
@Suite("CLIRunner")
struct CLIRunnerTests {
    /// True while any process whose command line contains `marker` is running.
    private func isRunning(marker: String) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-f", marker]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    @Test("Output and exit code come back")
    func capturesOutput() async throws {
        let result = try await CLIRunner.run(
            executable: "/bin/echo", arguments: ["hello", "world"])
        #expect(result.exitCode == 0)
        #expect(result.output == "hello world\n")
    }

    @Test("A non-zero exit is reported, not thrown")
    func reportsExitCode() async throws {
        let result = try await CLIRunner.run(
            executable: "/bin/sh", arguments: ["-c", "exit 3"])
        #expect(result.exitCode == 3)
    }

    @Test("stdout and stderr both stream through onLine")
    func streamsBothStreams() async throws {
        var lines: [String] = []
        let result = try await CLIRunner.run(
            executable: "/bin/sh", arguments: ["-c", "echo out; echo err 1>&2"]
        ) { lines.append($0) }
        #expect(result.exitCode == 0)
        #expect(lines.sorted() == ["err", "out"])
    }

    @Test("Cancelling stops the child and throws promptly")
    func cancellationStopsTheChild() async throws {
        // A distinctive duration so pgrep can only match this test's child.
        let marker = "3671.\(Int.random(in: 10...99))"
        let started = ContinuousClock.now

        let task = Task {
            try await CLIRunner.run(executable: "/bin/sleep", arguments: [marker])
        }
        // Let it get as far as having a pid to signal.
        while !isRunning(marker: marker) {
            try await Task.sleep(for: .milliseconds(20))
            #expect(started.duration(to: .now) < .seconds(10), "child never started")
        }

        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }

        // The point: it returns immediately rather than after the full sleep…
        #expect(started.duration(to: .now) < .seconds(10))
        // …and the child is actually gone, not orphaned.
        #expect(isRunning(marker: marker) == false)
    }

    @Test("Cancelling before the child exists still stops it")
    func cancellationBeforeStart() async throws {
        let marker = "3672.\(Int.random(in: 10...99))"
        let task = Task {
            try await CLIRunner.run(executable: "/bin/sleep", arguments: [marker])
        }
        // No wait: this races the process actually being spawned, which is the case
        // the cancelled-before-start path exists for.
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
        // Give a late-spawning child a moment to appear if it was going to.
        try await Task.sleep(for: .milliseconds(300))
        #expect(isRunning(marker: marker) == false)
    }

    @Test("An uncancelled run is unaffected")
    func normalRunIsNotDisturbed() async throws {
        let result = try await CLIRunner.run(executable: "/bin/sleep", arguments: ["0.2"])
        #expect(result.exitCode == 0)
    }
}
