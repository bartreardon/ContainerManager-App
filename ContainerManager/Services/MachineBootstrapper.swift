//
//  MachineBootstrapper.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import ContainerizationError
import Foundation
import MachineAPIClient

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
        }

        guard !snapshot.initialized else {
            return snapshot
        }

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
            try? await client.stop(id: snapshot.id)
            throw error
        }

        return snapshot
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
        throw originalError
    }
}
