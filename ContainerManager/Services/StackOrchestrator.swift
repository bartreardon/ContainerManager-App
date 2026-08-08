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
    ///
    /// Deliberately `nonisolated`: the target defaults to `MainActor` isolation, and
    /// pulling and unpacking images on the main actor blocks the UI for the whole run —
    /// the create sheet can't even scroll. Only the callbacks hop back.
    @discardableResult
    nonisolated static func run(
        spec: StackSpec,
        progress: GuiProgress,
        onStep: @escaping @MainActor (String) -> Void
    ) async throws -> URL? {
        // Fail before creating anything — a problem in the last service would otherwise
        // strand the earlier ones.
        let issues = StackValidator.issues(in: spec)
        guard issues.isEmpty else {
            await onStep("Nothing was created — \(issues.count) problem\(issues.count == 1 ? "" : "s") found.")
            throw StackValidator.Failure(issues: issues)
        }

        await onStep("Creating network “\(spec.networkName)”…")
        try await ensureNetwork(named: spec.networkName, for: spec.name)
        await ensureVolumes(for: spec)

        // Only dependencies are worth waiting for; see referencedRoles.
        let awaited = referencedRoles(in: spec)
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
                if awaited.contains(service.key) {
                    await waitUntilReady(service, host: ip, onStep: onStep)
                }
            }
        }

        await onStep("Stack “\(spec.name)” is up.")
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
    nonisolated private static func waitUntilReady(
        _ service: StackServiceSpec,
        host: String,
        onStep: @escaping @MainActor (String) -> Void
    ) async {
        // Without an address there's nothing to probe; waiting would just burn the
        // timeout against nothing.
        guard !host.isEmpty, host != "0.0.0.0" else {
            await onStep("\(service.displayName) has no address yet — not waiting for it.")
            return
        }
        for port in containerPorts(in: service.publishPorts) {
            // Name the address: a wait that never succeeds is usually the wrong target,
            // and that's invisible if the log only mentions the port.
            await onStep("Waiting for \(service.displayName) on \(host):\(port)…")
            let ready = await PortProbe.waitUntilAccepting(host: host, port: port, timeout: .seconds(120))
            await onStep(
                ready
                    ? "\(service.displayName) is ready."
                    : "\(service.displayName) isn’t listening on \(host):\(port) yet — continuing.")
        }
    }

    /// Service keys that other services address by IP. Only these are worth waiting on:
    /// waiting for a service nothing depends on (typically the last one, the app itself)
    /// just stalls for the timeout after all the work is already done.
    nonisolated static func referencedRoles(in spec: StackSpec) -> Set<String> {
        var roles: Set<String> = []
        for service in spec.services {
            for entry in service.env {
                var rest = Substring(entry)
                while let start = rest.range(of: "${IP:") {
                    guard let end = rest[start.upperBound...].firstIndex(of: "}") else { break }
                    roles.insert(String(rest[start.upperBound..<end]))
                    rest = rest[rest.index(after: end)...]
                }
            }
        }
        return roles
    }

    /// Container-side ports from "[host-ip:]host:container[/proto]" publish specs.
    nonisolated static func containerPorts(in specs: [String]) -> [UInt16] {
        specs.compactMap { spec in
            let withoutProtocol = spec.split(separator: "/").first.map(String.init) ?? spec
            return withoutProtocol.split(separator: ":").last.flatMap { UInt16($0) }
        }
    }

    /// Creates the stack's named volumes up front, labelled with the stack they belong
    /// to. The runtime would create them implicitly on first mount, but only labels a
    /// volume at creation and offers no way to set one later — so claiming them here is
    /// the only chance to record the association durably, and it outlives the stack.
    nonisolated static func ensureVolumes(for spec: StackSpec) async {
        let names = Set(spec.services.flatMap { $0.volumes.compactMap(VolumeGrouping.volumeName(inMount:)) })
        guard !names.isEmpty else { return }
        let existing = Set(((try? await ClientVolume.list()) ?? []).map(\.name))
        for name in names.subtracting(existing).sorted() {
            _ = try? await ClientVolume.create(name: name, labels: [StackLabels.stack: spec.name])
        }
    }

    /// Creates the stack's network, labelled with the stack it belongs to so the
    /// association is recorded rather than inferred from the `<stack>-net` name.
    nonisolated static func ensureNetwork(named name: String, for stack: String? = nil) async throws {
        let client = NetworkClient()
        let existing = try await client.list()
        guard !existing.contains(where: { $0.name == name }) else { return }
        let labels = try stack.map { try ResourceLabels([StackLabels.stack: $0]) } ?? ResourceLabels()
        let config = try NetworkConfiguration(
            name: name, mode: .nat, labels: labels, plugin: "container-network-vmnet")
        _ = try await client.create(configuration: config)
    }

    nonisolated static func resolve(_ value: String, ips: [String: String]) -> String {
        var result = value
        for (key, ip) in ips {
            result = result.replacingOccurrences(of: StackToken.ip(key), with: ip)
        }
        return result
    }
}
