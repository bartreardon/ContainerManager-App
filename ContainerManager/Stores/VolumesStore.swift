//
//  VolumesStore.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import Foundation
import Observation

@Observable
final class VolumesStore {
    private(set) var volumes: [VolumeConfiguration] = []
    /// Disk usage in bytes keyed by volume name, filled best-effort after refresh.
    private(set) var sizes: [String: UInt64] = [:]
    private(set) var busyIds: Set<String> = []
    var lastError: PresentedError?

    func volume(withId id: String) -> VolumeConfiguration? {
        volumes.first { $0.id == id }
    }

    func isBusy(_ id: String) -> Bool {
        busyIds.contains(id)
    }

    /// Names suitable for attaching to a container (excludes anonymous volumes).
    var selectableNames: [String] {
        volumes.filter { !$0.isAnonymous }.map(\.name)
    }

    func refresh() async {
        do {
            volumes = try await ClientVolume.list().sorted { $0.name < $1.name }
            await updateSizes()
        } catch {
            lastError = PresentedError(title: "Failed to load volumes", error: error)
        }
    }

    func create(name: String) async throws {
        _ = try await ClientVolume.create(name: name)
        await refresh()
    }

    func delete(id: String) async {
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            try await ClientVolume.delete(name: id)
        } catch {
            lastError = PresentedError(title: "Failed to delete volume", error: error)
        }
        await refresh()
    }

    private func updateSizes() async {
        for volume in volumes where sizes[volume.name] == nil {
            if let size = try? await ClientVolume.volumeDiskUsage(name: volume.name) {
                sizes[volume.name] = size
            }
        }
    }
}
