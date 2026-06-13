//
//  SystemStore.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerPlugin
import Foundation
import Observation

/// Tracks whether the `container` system services are installed and running,
/// and starts/stops them via the CLI. All other stores are gated on this one.
@Observable
final class SystemStore {
    static let apiServerLabel = "com.apple.container.apiserver"

    private(set) var status: DaemonStatus = .unknown
    private(set) var health: SystemHealth?
    private(set) var actionOutput: [String] = []
    var lastError: PresentedError?

    var isRunning: Bool { status == .running }

    func refresh() async {
        if status == .starting || status == .stopping {
            return
        }
        // Check for a live daemon before requiring a CLI: a daemon installed in a
        // non-standard location is still fully manageable, and a successful ping
        // teaches us where its CLI lives.
        let label = Self.apiServerLabel
        let registered = await Task.detached {
            (try? ServiceManager.isRegistered(fullServiceLabel: label)) ?? false
        }.value
        if registered {
            do {
                let health = try await ClientHealthCheck.ping(timeout: .seconds(3))
                CLIPathResolver.observe(health: health)
                self.health = health
                status = .running
                return
            } catch {
                // Registered but unresponsive — treat as stopped below.
            }
        }
        health = nil
        status = CLIRunner.isInstalled ? .stopped : .notInstalled
    }

    func start() async {
        guard status == .stopped || status == .unknown else { return }
        status = .starting
        actionOutput = []
        do {
            // --enable-kernel-install answers the CLI's interactive kernel prompt.
            // The first start downloads a kernel and init filesystem; no timeout here.
            let result = try await CLIRunner.run(["system", "start", "--enable-kernel-install"]) { [weak self] line in
                self?.actionOutput.append(line)
            }
            if result.exitCode != 0 {
                lastError = PresentedError(title: "Failed to start container services", message: result.output)
            }
        } catch {
            lastError = PresentedError(title: "Failed to start container services", error: error)
        }
        status = .unknown
        await refresh()
    }

    func stop() async {
        guard status == .running else { return }
        status = .stopping
        do {
            let result = try await CLIRunner.run(["system", "stop"])
            if result.exitCode != 0 {
                lastError = PresentedError(title: "Failed to stop container services", message: result.output)
            }
        } catch {
            lastError = PresentedError(title: "Failed to stop container services", error: error)
        }
        status = .unknown
        health = nil
        await refresh()
    }
}
