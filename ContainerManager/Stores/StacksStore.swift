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
                .map { Stack(name: $0.key, services: $0.value.sorted { $0.id < $1.id }) }
                .sorted { $0.name < $1.name }
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
