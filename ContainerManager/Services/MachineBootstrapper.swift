//
//  MachineBootstrapper.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import ContainerizationError
import Foundation
import MachineAPIClient

/// A machine boot failure enriched with the tail of the machine's logs and a hint
/// about the most common cause (images without an init system).
struct MachineBootFailure: LocalizedError {
    let underlying: String
    let logTail: String?

    var errorDescription: String? {
        var text = underlying
        if let logTail, !logTail.isEmpty {
            text += "\n\nLast log lines:\n\(logTail)"
        }
        text += "\n\nHint: machine images must include an init system at /sbin/init. alpine works out of the box; plain ubuntu/debian images do not (see the container-machine docs)."
        return text
    }
}

enum MachineBootstrapper {
    /// Boots a machine and, on its first ever boot, runs the in-VM init binary to
    /// create the host user inside the machine. Mirrors the container CLI's internal
    /// `bootMachine` helper (non-interactive path). On failure during user setup the
    /// machine is stopped so it isn't left half-initialized.
    @discardableResult
    static func bootAndInitialize(id: String) async throws -> MachineSnapshot {
        let client = MachineClient()

        var dynamicEnv: [String: String] = [:]
        if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            dynamicEnv["SSH_AUTH_SOCK"] = sshAuthSock
        }
        let snapshot: MachineSnapshot
        do {
            snapshot = try await client.boot(id: id, dynamicEnv: dynamicEnv)
        } catch where isXPCTimeout(error) {
            // A first boot can outlast the client's fixed 10-second XPC timeout while
            // the VM is still coming up. Poll for it to reach running before failing.
            snapshot = try await waitForRunning(id: id, client: client, originalError: error)
        } catch {
            throw MachineBootFailure(
                underlying: PresentedError.describe(error),
                logTail: await tailLogs(id: id)
            )
        }

        if !snapshot.initialized {
            do {
                guard let containerId = snapshot.containerId else {
                    throw ContainerizationError(
                        .invalidState,
                        message: "container machine is running but has no container ID"
                    )
                }

                let io = try ProcessIO.create(tty: false, interactive: false, detach: true)
                defer { try? io.close() }

                let processConfig = ProcessConfiguration(
                    executable: "/\(MachineBundle.sbinDirectory)/\(MachineBundle.initFile)",
                    arguments: ["-u"],
                    environment: snapshot.configuration.processEnvironment,
                    terminal: false
                )

                let process = try await ContainerClient().createProcess(
                    containerId: containerId,
                    processId: UUID().uuidString.lowercased(),
                    configuration: processConfig,
                    stdio: io.stdio
                )

                try await process.start()
                try io.closeAfterStart()
                let exitCode = try await process.wait()
                guard exitCode == 0 else {
                    throw ContainerizationError(
                        .invalidState,
                        message: "container machine failed to create user"
                    )
                }
            } catch {
                let tail = await tailLogs(id: id)
                try? await client.stop(id: snapshot.id)
                throw MachineBootFailure(
                    underlying: PresentedError.describe(error),
                    logTail: tail
                )
            }
        }

        // Images without /sbin/init "boot" successfully and then die immediately.
        // Catch that case so the user gets the log tail instead of a silent stop.
        try? await Task.sleep(for: .seconds(2))
        if let check = try? await client.inspect(id: id), check.status != .running {
            throw MachineBootFailure(
                underlying: "the machine exited immediately after booting",
                logTail: await tailLogs(id: id)
            )
        }

        return snapshot
    }

    /// Returns the last few lines of the machine's logs, preferring the boot log.
    static func tailLogs(id: String, lines: Int = 8) async -> String? {
        guard let handles = try? await MachineClient().logs(id: id) else {
            return nil
        }
        defer {
            for handle in handles {
                try? handle.close()
            }
        }
        for index in [1, 0] where handles.indices.contains(index) {
            guard
                let data = try? handles[index].readToEnd(),
                !data.isEmpty
            else { continue }
            let text = String(decoding: data, as: UTF8.self)
            let tail = text
                .split(separator: "\n", omittingEmptySubsequences: true)
                .suffix(lines)
                .joined(separator: "\n")
            if !tail.isEmpty {
                return tail
            }
        }
        return nil
    }

    private static func isXPCTimeout(_ error: any Error) -> Bool {
        String(describing: error).contains("XPC timeout")
    }

    private static func waitForRunning(
        id: String,
        client: MachineClient,
        originalError: any Error
    ) async throws -> MachineSnapshot {
        for _ in 0..<25 {
            try? await Task.sleep(for: .seconds(2))
            if let snapshot = try? await client.inspect(id: id), snapshot.status == .running {
                return snapshot
            }
        }
        throw MachineBootFailure(
            underlying: PresentedError.describe(originalError),
            logTail: await tailLogs(id: id)
        )
    }
}
