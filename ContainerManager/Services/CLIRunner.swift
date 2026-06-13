//
//  CLIRunner.swift
//  ContainerManager
//

import Foundation

struct CLIResult {
    let exitCode: Int32
    let output: String
}

/// Runs the installed `container` CLI for the few operations that aren't practical
/// to perform in-process (registering and deregistering the launchd services).
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

    @discardableResult
    static func run(_ arguments: [String], onLine: ((String) -> Void)? = nil) async throws -> CLIResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: containerBinary)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()

        var output = ""
        for try await line in pipe.fileHandleForReading.bytes.lines {
            output += line + "\n"
            onLine?(line)
        }
        // EOF means the process closed its end of the pipe; give it a moment to exit.
        while process.isRunning {
            try? await Task.sleep(for: .milliseconds(50))
        }
        return CLIResult(exitCode: process.terminationStatus, output: output)
    }
}
