//
//  CLIRunner.swift
//  ContainerManager
//

import Darwin
import Foundation
import Synchronization

struct CLIResult {
    let exitCode: Int32
    let output: String
}

/// Runs the installed `container` CLI for the few operations that aren't practical
/// to perform in-process (registering and deregistering the launchd services, and
/// `build`, which streams BuildKit progress as plain text).
enum CLIRunner {
    /// Path to the container CLI; see CLIPathResolver for the resolution order.
    /// A dev build can be forced via:
    ///   defaults write com.bartreardon.ContainerManager containerBinaryPath <path>
    static var containerBinary: String {
        CLIPathResolver.effectivePath ?? CLIPathResolver.standardPath
    }

    static var isInstalled: Bool {
        CLIPathResolver.effectivePath != nil
    }

    /// What the cancellation handler needs to stop the child. It runs on an arbitrary
    /// thread, so it gets the pid — a value that can cross safely — rather than the
    /// `Process`, which can't.
    private nonisolated struct Child {
        var pid: pid_t = 0
        var cancelled = false
    }

    /// Runs the CLI, streaming each output line to `onLine`, and returns once the
    /// child has exited.
    ///
    /// Cancelling the surrounding task sends the child `SIGTERM` and throws
    /// `CancellationError` — without this a long `container build` could not be
    /// stopped from the interface at all.
    @discardableResult
    static func run(_ arguments: [String], onLine: ((String) -> Void)? = nil) async throws -> CLIResult {
        try await run(executable: containerBinary, arguments: arguments, onLine: onLine)
    }

    /// The above, with the executable named — the seam the cancellation tests use, so
    /// they don't depend on the CLI being installed or on what a real build does.
    @discardableResult
    static func run(
        executable: String, arguments: [String], onLine: ((String) -> Void)? = nil
    ) async throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        let child = Mutex(Child())
        let exited = ProcessExit()
        // Installed before `run` so termination can't be missed.
        process.terminationHandler = { _ in exited.signal() }

        return try await withTaskCancellationHandler {
            try process.run()
            // Cancellation can arrive between the handler being installed and the child
            // existing, in which case there was no pid to signal — stop it here.
            let cancelledBeforeStart = child.withLock { child -> Bool in
                child.pid = process.processIdentifier
                return child.cancelled
            }
            if cancelledBeforeStart { process.terminate() }

            var output = ""
            for try await line in pipe.fileHandleForReading.bytes.lines {
                output += line + "\n"
                onLine?(line)
            }
            // EOF means the child closed its end of the pipe, not that it has exited.
            await exited.wait()
            // Report a cancelled run as cancelled, rather than as the signal's exit code.
            try Task.checkCancellation()
            return CLIResult(exitCode: process.terminationStatus, output: output)
        } onCancel: {
            child.withLock { child in
                child.cancelled = true
                if child.pid > 0 { kill(child.pid, SIGTERM) }
            }
        }
    }
}

/// Bridges `Process.terminationHandler` — which fires on an arbitrary thread, and may
/// fire before anything is waiting — to a single `await`.
private nonisolated final class ProcessExit: Sendable {
    private struct State {
        var hasExited = false
        var waiter: CheckedContinuation<Void, Never>?
    }

    private let state = Mutex(State())

    func signal() {
        // Resumed outside the lock: a continuation can run arbitrary work.
        let waiter = state.withLock { state -> CheckedContinuation<Void, Never>? in
            state.hasExited = true
            defer { state.waiter = nil }
            return state.waiter
        }
        waiter?.resume()
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            let alreadyExited = state.withLock { state -> Bool in
                guard !state.hasExited else { return true }
                state.waiter = continuation
                return false
            }
            if alreadyExited { continuation.resume() }
        }
    }
}
