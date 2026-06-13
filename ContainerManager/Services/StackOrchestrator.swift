//
//  StackOrchestrator.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import ContainerizationExtras
import Foundation

/// Stands up a multi-container stack: creates the network, then creates and starts
/// each service in order, injecting earlier services' IPs into later services' env.
enum StackOrchestrator {
    /// Runs the plan. `onStep` reports high-level progress lines; `progress` carries
    /// image fetch/unpack progress. Returns the web URL if the stack exposes one.
    @discardableResult
    static func run(
        spec: StackSpec,
        progress: GuiProgress,
        onStep: @escaping @MainActor (String) -> Void
    ) async throws -> URL? {
        await onStep("Creating network “\(spec.networkName)”…")
        try await ensureNetwork(named: spec.networkName)

        var ips: [String: String] = [:]
        for service in spec.services {
            let containerName = "\(spec.name)-\(service.key)"
            await onStep("Starting \(service.displayName) (\(containerName))…")

            let env = service.env.map { resolve($0, ips: ips) }

            var labels = [
                "\(StackLabels.stack)=\(spec.name)",
                "\(StackLabels.role)=\(service.key)",
            ]
            if service.key == spec.webServiceKey, let port = spec.webPort {
                labels.append("\(StackLabels.url)=http://localhost:\(port)")
            }

            let containerSpec = ContainerCreateSpec(
                name: containerName,
                image: service.image,
                command: "",
                env: env,
                cpus: nil,
                memory: nil,
                network: spec.networkName,
                publishPorts: service.publishPorts,
                volumes: service.volumes,
                labels: labels,
                autoRemove: false,
                startAfterCreate: false
            )

            let id = try await ContainerLauncher.create(spec: containerSpec, progress: progress, start: true)

            if let snapshot = try? await ContainerClient().get(id: id),
                let address = snapshot.networks.first?.ipv4Address {
                ips[service.key] = "\(address)".withoutCIDRSuffix
            }
        }

        await onStep("Stack “\(spec.name)” is up.")
        if let port = spec.webPort, spec.webServiceKey != nil {
            return URL(string: "http://localhost:\(port)")
        }
        return nil
    }

    private static func ensureNetwork(named name: String) async throws {
        let client = NetworkClient()
        let existing = try await client.list()
        guard !existing.contains(where: { $0.name == name }) else { return }
        let config = try NetworkConfiguration(name: name, mode: .nat, plugin: "container-network-vmnet")
        _ = try await client.create(configuration: config)
    }

    private static func resolve(_ value: String, ips: [String: String]) -> String {
        var result = value
        for (key, ip) in ips {
            result = result.replacingOccurrences(of: StackToken.ip(key), with: ip)
        }
        return result
    }
}
