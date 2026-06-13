//
//  ContainersStore.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import ContainerizationError
import Foundation
import Observation

struct ContainerCreateSpec {
    var name: String
    var image: String
    /// Whitespace-tokenized into process arguments; empty uses the image default.
    var command: String
    /// KEY=VALUE entries.
    var env: [String]
    var cpus: Int64?
    var memory: String?
    /// Network name; "default" maps to the built-in network (empty attachment list).
    var network: String
    /// "[host-ip:]host-port:container-port[/protocol]" entries.
    var publishPorts: [String]
    /// Volume/bind mount specs: "name:/path" (named volume) or "/host:/path[:ro]" (bind).
    var volumes: [String]
    /// Labels as "key=value" entries.
    var labels: [String] = []
    var autoRemove: Bool
    var startAfterCreate: Bool
}

@Observable
final class ContainersStore {
    private(set) var containers: [ContainerSnapshot] = []
    private(set) var busyIds: Set<String> = []
    var lastError: PresentedError?

    func container(withId id: String) -> ContainerSnapshot? {
        containers.first { $0.id == id }
    }

    func isBusy(_ id: String) -> Bool {
        busyIds.contains(id)
    }

    func refresh() async {
        do {
            // Machines are backed by containers; hide those like the CLI does.
            let filters = ContainerListFilters().withoutMachines()
            containers = try await ContainerClient().list(filters: filters).sorted { $0.id < $1.id }
        } catch {
            lastError = PresentedError(title: "Failed to load containers", error: error)
        }
    }

    /// Creates a container via the shared launcher and refreshes the list.
    /// Throws so the create sheet can surface failures inline.
    func create(spec: ContainerCreateSpec, progress: GuiProgress) async throws {
        try await ContainerLauncher.create(spec: spec, progress: progress, start: spec.startAfterCreate)
        await refresh()
    }

    func start(id: String) async {
        await perform(id: id, title: "Failed to start container") {
            let client = ContainerClient()
            let container = try await client.get(id: id)
            guard container.status != .running else { return }
            try await ContainerLauncher.startDetached(
                id: id,
                tty: container.configuration.initProcess.terminal,
                client: client
            )
        }
    }

    func stop(id: String) async {
        await perform(id: id, title: "Failed to stop container") {
            try await ContainerClient().stop(id: id)
        }
    }

    func kill(id: String) async {
        await perform(id: id, title: "Failed to kill container") {
            try await ContainerClient().kill(id: id, signal: "KILL")
        }
    }

    func delete(id: String, force: Bool) async {
        await perform(id: id, title: "Failed to delete container") {
            try await ContainerClient().delete(id: id, force: force)
        }
    }

    private func perform(id: String, title: String, _ action: () async throws -> Void) async {
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            try await action()
        } catch {
            lastError = PresentedError(title: title, error: error)
        }
        await refresh()
    }
}
