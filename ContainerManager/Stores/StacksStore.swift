//
//  StacksStore.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import Foundation
import Observation

/// A group of containers created together as a stack, identified by a shared label.
struct Stack: Identifiable {
    let name: String
    let services: [ContainerSnapshot]
    /// User-facing name (custom, or the internal name) and icon; see `StackMetadata`.
    var displayName: String
    var icon: String

    var id: String { name }

    var runningCount: Int {
        services.filter { $0.status == .running }.count
    }

    var allRunning: Bool {
        !services.isEmpty && services.allSatisfy { $0.status == .running }
    }

    var anyRunning: Bool {
        services.contains { $0.status == .running }
    }

    var webURL: URL? {
        services
            .compactMap { $0.configuration.labels[StackLabels.url] }
            .first
            .flatMap(URL.init)
    }

    /// The dedicated network created for this stack (by convention).
    var networkName: String { "\(name)-net" }

    /// Named volumes this stack's services mount, and where each is mounted. Stacks are
    /// grouped by label at runtime, so this is the only place the association is visible.
    var volumes: [StackVolume] {
        var mountsByVolume: [String: [String]] = [:]
        for service in services {
            let role = service.configuration.labels[StackLabels.role] ?? service.id
            for mount in service.configuration.mounts {
                guard let name = mount.volumeName else { continue }
                let readOnly = mount.options.readonly ? " (read-only)" : ""
                mountsByVolume[name, default: []].append("\(role) → \(mount.destination)\(readOnly)")
            }
        }
        return
            mountsByVolume
            .map { StackVolume(name: $0.key, mounts: $0.value.sorted()) }
            .sorted { $0.name < $1.name }
    }
}

/// A named volume used by a stack, with the services that mount it.
struct StackVolume: Identifiable {
    let name: String
    /// "role → /path" entries, one per mount.
    let mounts: [String]

    var id: String { name }
}

@Observable
final class StacksStore {
    private(set) var stacks: [Stack] = []
    private(set) var busyNames: Set<String> = []
    var lastError: PresentedError?

    func stack(named name: String) -> Stack? {
        stacks.first { $0.name == name }
    }

    func isBusy(_ name: String) -> Bool {
        busyNames.contains(name)
    }

    func refresh() async {
        do {
            let containers = try await ContainerClient().list(filters: ContainerListFilters().withoutMachines())
            var groups: [String: [ContainerSnapshot]] = [:]
            for container in containers {
                guard let name = container.configuration.labels[StackLabels.stack] else { continue }
                groups[name, default: []].append(container)
            }
            stacks = groups
                .map { name, services in
                    let meta = StackMetadata.get(name)
                    return Stack(
                        name: name,
                        services: services.sorted { $0.id < $1.id },
                        displayName: meta.displayName ?? name,
                        icon: meta.icon ?? StackIcons.default
                    )
                }
                .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        } catch {
            lastError = PresentedError(title: "Failed to load stacks", error: error)
        }
    }

    func start(name: String) async {
        await perform(name: name, title: "Failed to start stack") {
            guard let stack = self.stack(named: name) else { return }
            let client = ContainerClient()
            for service in stack.services where service.status != .running {
                try await ContainerLauncher.startDetached(
                    id: service.id,
                    tty: service.configuration.initProcess.terminal,
                    client: client
                )
            }
        }
    }

    func stop(name: String) async {
        await perform(name: name, title: "Failed to stop stack") {
            guard let stack = self.stack(named: name) else { return }
            let client = ContainerClient()
            for service in stack.services where service.status == .running {
                try await client.stop(id: service.id)
            }
        }
    }

    /// Adds a service to an existing stack — or replaces one, which is how a service
    /// that failed to create (or needs different settings) gets repaired. The stack's
    /// labels and network are applied so the new container joins the group.
    func addService(
        to stackName: String,
        service: StackServiceSpec,
        replacing: ContainerSnapshot?,
        webURL: String? = nil,
        progress: GuiProgress
    ) async throws {
        let plan = StackSpec(
            name: stackName, networkName: "\(stackName)-net", services: [service],
            webServiceKey: nil, webPort: nil)
        let issues = StackValidator.issues(in: plan)
        guard issues.isEmpty else { throw StackValidator.Failure(issues: issues) }

        try await StackOrchestrator.ensureNetwork(named: "\(stackName)-net")
        // Claim any new named volumes so they carry the stack label too.
        await StackOrchestrator.ensureVolumes(for: plan)

        var labels = [
            "\(StackLabels.stack)=\(stackName)",
            "\(StackLabels.role)=\(service.key)",
        ]
        // Keep the web-URL label so "Open in Browser" survives a replacement.
        let url = webURL?.trimmingCharacters(in: .whitespaces)
        if let url, !url.isEmpty {
            labels.append("\(StackLabels.url)=\(url)")
        } else if url == nil, let existing = replacing?.configuration.labels[StackLabels.url] {
            labels.append("\(StackLabels.url)=\(existing)")
        }

        // Resolve ${IP:role} against the stack's running services, exactly as the
        // orchestrator does when standing a stack up — otherwise env copied from a
        // stack definition would reach the container as a literal token.
        var ips: [String: String] = [:]
        for member in stack(named: stackName)?.services ?? [] where member.id != replacing?.id {
            let role = member.configuration.labels[StackLabels.role] ?? member.id
            if let address = member.networks.first?.ipv4Address {
                ips[role] = "\(address)".withoutCIDRSuffix
            }
        }
        let env = service.env.map { StackOrchestrator.resolve($0, ips: ips) }

        if let replacing {
            let client = ContainerClient()
            try? await client.stop(id: replacing.id)
            try? await client.delete(id: replacing.id, force: true)
        }

        let spec = ContainerCreateSpec(
            name: "\(stackName)-\(service.key)",
            image: service.image,
            command: service.command,
            env: env,
            cpus: nil,
            memory: nil,
            network: "\(stackName)-net",
            publishPorts: service.publishPorts,
            volumes: service.volumes,
            labels: labels,
            platform: service.platform,
            autoRemove: false,
            startAfterCreate: false
        )
        try await ContainerLauncher.create(spec: spec, progress: progress, start: true)
        await refresh()
    }

    /// Removes a single service's container, leaving the rest of the stack in place.
    func removeService(id: String, from stackName: String) async {
        await perform(name: stackName, title: "Failed to remove service") {
            let client = ContainerClient()
            try? await client.stop(id: id)
            try await client.delete(id: id, force: true)
        }
    }

    /// Stops and deletes all member containers and removes the stack network.
    /// Named volumes are intentionally left in place to preserve data.
    func delete(name: String) async {
        await perform(name: name, title: "Failed to delete stack") {
            guard let stack = self.stack(named: name) else { return }
            let client = ContainerClient()
            for service in stack.services {
                try? await client.stop(id: service.id)
                try await client.delete(id: service.id, force: true)
            }
            try? await NetworkClient().delete(id: stack.networkName)
            // The stashed definition can hold credentials, so it goes with the stack.
            StackDefinitionStore.delete(for: name)
        }
    }

    /// Services the stack was defined with that aren't present right now — what a
    /// failed create leaves behind. Empty when the stack has no stashed definition.
    func missingServices(in stack: Stack) -> [StackServiceSpec] {
        guard let plan = StackDefinitionStore.load(for: stack.name)?.plan() else { return [] }
        let present = Set(stack.services.map { $0.configuration.labels[StackLabels.role] ?? $0.id })
        return plan.services.filter { !present.contains($0.key) }
    }

    /// Re-creates every service missing from the stack, using its stashed definition.
    func recreateMissingServices(in stack: Stack, progress: GuiProgress) async {
        guard let plan = StackDefinitionStore.load(for: stack.name)?.plan() else { return }
        let missing = missingServices(in: stack)
        await perform(name: stack.name, title: "Failed to re-create services") {
            for service in missing {
                // Restore the web-URL label if this is the stack's web service.
                var webURL: String?
                if service.key == plan.webServiceKey, let port = plan.webPort {
                    webURL = "http://localhost:\(port)"
                }
                try await self.addService(
                    to: stack.name, service: service, replacing: nil, webURL: webURL, progress: progress)
            }
        }
    }

    private func perform(name: String, title: String, _ action: () async throws -> Void) async {
        busyNames.insert(name)
        defer { busyNames.remove(name) }
        do {
            try await action()
        } catch {
            lastError = PresentedError(title: title, error: error)
        }
        await refresh()
    }
}
