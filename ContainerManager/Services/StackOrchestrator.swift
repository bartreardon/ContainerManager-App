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
    @MainActor @discardableResult
    static func run(
        spec: StackSpec,
        progress: GuiProgress,
        onStep: @escaping @MainActor (String) -> Void
    ) async throws -> URL? {
        onStep("Creating network “\(spec.networkName)”…")
        try await ensureNetwork(named: spec.networkName)

        var ips: [String: String] = [:]
        for service in spec.services {
            let containerName = "\(spec.name)-\(service.key)"
            onStep("Starting \(service.displayName) (\(containerName))…")

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
                command: service.command,
                env: env,
                cpus: nil,
                memory: nil,
                network: spec.networkName,
                publishPorts: service.publishPorts,
                volumes: service.volumes,
                labels: labels,
                platform: service.platform,
                autoRemove: false,
                startAfterCreate: false
            )

            let id = try await ContainerLauncher.create(spec: containerSpec, progress: progress, start: true)

            if let snapshot = try? await ContainerClient().get(id: id),
                let address = snapshot.networks.first?.ipv4Address {
                let ip = "\(address)".withoutCIDRSuffix
                ips[service.key] = ip
                await waitUntilReady(service, host: ip, onStep: onStep)
            }
        }

        onStep("Stack “\(spec.name)” is up.")
        if let port = spec.webPort, spec.webServiceKey != nil {
            return URL(string: "http://localhost:\(port)")
        }
        return nil
    }

    /// Waits for a service to accept connections on the ports it exposes.
    ///
    /// Compose's `depends_on: condition: service_healthy` can't be honoured directly, and
    /// services are started in order but "started" isn't "ready" — a database
    /// initialising a fresh volume can take a minute, while a dependent that connects on
    /// startup (Fleet runs `fleet prepare db` immediately) fails outright against it.
    /// A timeout here isn't fatal: the service may simply not listen on a TCP port.
    private static func waitUntilReady(
        _ service: StackServiceSpec,
        host: String,
        onStep: @escaping @MainActor (String) -> Void
    ) async {
        for port in containerPorts(in: service.publishPorts) {
            onStep("Waiting for \(service.displayName) to accept connections on \(port)…")
            let ready = await PortProbe.waitUntilAccepting(host: host, port: port, timeout: .seconds(120))
            onStep(
                ready
                    ? "\(service.displayName) is ready."
                    : "\(service.displayName) isn’t listening on \(port) yet — continuing.")
        }
    }

    /// Container-side ports from "[host-ip:]host:container[/proto]" publish specs.
    private static func containerPorts(in specs: [String]) -> [UInt16] {
        specs.compactMap { spec in
            let withoutProtocol = spec.split(separator: "/").first.map(String.init) ?? spec
            return withoutProtocol.split(separator: ":").last.flatMap { UInt16($0) }
        }
    }

    static func ensureNetwork(named name: String) async throws {
        let client = NetworkClient()
        let existing = try await client.list()
        guard !existing.contains(where: { $0.name == name }) else { return }
        let config = try NetworkConfiguration(name: name, mode: .nat, plugin: "container-network-vmnet")
        _ = try await client.create(configuration: config)
    }

    static func resolve(_ value: String, ips: [String: String]) -> String {
        var result = value
        for (key, ip) in ips {
            result = result.replacingOccurrences(of: StackToken.ip(key), with: ip)
        }
        return result
    }
}
