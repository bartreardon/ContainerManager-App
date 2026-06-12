//
//  ContainersStore.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import Foundation
import Observation

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
