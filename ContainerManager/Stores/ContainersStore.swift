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
    /// OCI platform (e.g. "linux/amd64") for multi-platform images; nil uses the host's.
    /// Apple silicon runs linux/amd64 images under emulation.
    var platform: String? = nil
    var autoRemove: Bool
    var startAfterCreate: Bool
    /// Settings the create sheets don't offer, used when re-creating a container exactly.
    var advanced = ContainerAdvancedSettings()
}

/// The rest of a container's configuration, for a faithful re-create. Defaults leave
/// the create path behaving as it always has.
struct ContainerAdvancedSettings: Equatable {
    /// Replaces the image's ENTRYPOINT; with it set, the image's CMD isn't appended.
    var entrypoint: String?
    /// Used as-is instead of splitting `command`.
    var arguments: [String]?
    var workingDirectory: String?
    var user: String?
    var tty = false
    /// "destination[:options]" entries.
    var tmpfs: [String] = []
    var readOnly = false
    var useInit = false
    var rosetta = false
    var ssh = false
    var virtualization = false
    var capAdd: [String] = []
    var capDrop: [String] = []
}

@Observable
final class ContainersStore {
    private(set) var containers: [ContainerSnapshot] = []
    private(set) var busyIds: Set<String> = []
    var lastError: PresentedError?

    /// Containers whose in-VM agent is too old to reclaim space. Their menus offer
    /// Re-create instead; the rest keep Reclaim Unused Space.
    private(set) var needsRecreateToReclaim: Set<String> = []
    /// A container whose Reclaim failed because its agent is too old, waiting on the
    /// user to re-create it or not.
    var recreateOffer: ReclaimSpace.NeedsRecreating?
    /// The container being re-created, and how far it's got.
    private(set) var recreating: (id: String, progress: GuiProgress)?
    /// The IDs `needsRecreateToReclaim` was worked out for; it's redone when they change.
    private var agentCheckedIDs: [String]?

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
        let ids = containers.map(\.id)
        if ids != agentCheckedIDs {
            agentCheckedIDs = ids
            needsRecreateToReclaim = await ContainerAgent.tooOldToReclaim(ids)
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

    /// Trims a running container's writable filesystems so the host reclaims freed space.
    func clean(id: String) async {
        await perform(id: id, title: "Failed to reclaim unused space") {
            do {
                try await ReclaimSpace.clean(id: id)
            } catch let needsRecreating as ReclaimSpace.NeedsRecreating {
                recreateOffer = needsRecreating
            }
        }
    }

    /// Rebuilds a container from its own settings on the current in-VM agent.
    func recreate(id: String) async {
        guard let container = container(withId: id) else { return }
        let progress = GuiProgress()
        recreating = (id, progress)
        defer { recreating = nil }
        await perform(id: id, title: "Failed to re-create container") {
            // Same ID, new agent: work out which containers need re-creating again.
            defer { agentCheckedIDs = nil }
            try await ContainerRecreation.recreate(container, progress: progress)
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
