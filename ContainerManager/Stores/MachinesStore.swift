//
//  MachinesStore.swift
//  ContainerManager
//

import ArgumentParser
import ContainerAPIClient
import ContainerPersistence
import ContainerizationOCI
import Foundation
import MachineAPIClient
import Observation

struct MachineCreateSpec {
    var name: String
    var image: String
    var cpus: Int
    var memory: String
    var homeMount: MachineConfig.HomeMountOption
    var setAsDefault: Bool
    var bootAfterCreate: Bool
}

@Observable
final class MachinesStore {
    private(set) var machines: [MachineSnapshot] = []
    private(set) var defaultId: String?
    private(set) var busyIds: Set<String> = []
    var lastError: PresentedError?

    func machine(withId id: String) -> MachineSnapshot? {
        machines.first { $0.id == id }
    }

    func isBusy(_ id: String) -> Bool {
        busyIds.contains(id)
    }

    func refresh() async {
        do {
            let client = MachineClient()
            async let list = client.list()
            async let defaultMachine = client.getDefault()
            machines = try await list.sorted { $0.id < $1.id }
            defaultId = try await defaultMachine
        } catch {
            lastError = PresentedError(title: "Failed to load machines", error: error)
        }
    }

    func boot(id: String) async {
        await perform(id: id, title: "Failed to start machine") {
            try await MachineBootstrapper.bootAndInitialize(id: id)
        }
    }

    func stop(id: String) async {
        await perform(id: id, title: "Failed to stop machine") {
            try await MachineClient().stop(id: id)
        }
    }

    func delete(id: String) async {
        await perform(id: id, title: "Failed to delete machine") {
            let client = MachineClient()
            // Mirror the CLI: stop is idempotent, then delete.
            try? await client.stop(id: id)
            try await client.delete(id: id)
        }
    }

    func setDefault(id: String) async {
        await perform(id: id, title: "Failed to set default machine") {
            try await MachineClient().setDefault(id: id)
        }
    }

    func applyBootConfig(id: String, cpus: Int, memory: String, homeMount: MachineConfig.HomeMountOption) async -> Bool {
        guard let snapshot = machine(withId: id) else { return false }
        do {
            let newConfig = try snapshot.bootConfig.with([
                "cpus": String(cpus),
                "memory": memory,
                "home-mount": homeMount.rawValue,
            ])
            try await MachineClient().setConfig(id: id, bootConfig: newConfig)
            await refresh()
            return true
        } catch {
            lastError = PresentedError(title: "Failed to update configuration", error: error)
            return false
        }
    }

    /// Creates a machine following the same pipeline as `container machine create`:
    /// fetch + unpack the image, create, then optionally set default and boot.
    /// Throws so the create sheet can surface failures inline.
    func create(spec: MachineCreateSpec, progress: GuiProgress) async throws {
        let systemConfig = try await ConfigurationLoader.load()
        let bootConfig = try systemConfig.machine.with([
            "cpus": String(spec.cpus),
            "memory": spec.memory,
            "home-mount": spec.homeMount.rawValue,
        ])

        let id = spec.name.isEmpty ? Self.derivedName(fromImage: spec.image) : spec.name
        try Utility.validEntityName(id)

        let client = MachineClient()
        let (config, resources) = try await MachineClient.machineConfigFromFlags(
            id: id,
            image: spec.image,
            management: Flags.MachineManagement.parse([]),
            registry: Flags.Registry(scheme: "auto"),
            imageFetch: Flags.ImageFetch(maxConcurrentDownloads: 3),
            containerSystemConfig: systemConfig,
            progressUpdate: progress.handler
        )

        progress.setPhase("Creating machine")
        try await client.create(configuration: config, resources: resources, bootConfig: bootConfig)

        if spec.setAsDefault {
            try await client.setDefault(id: id)
        }

        if spec.bootAfterCreate {
            progress.setPhase("Booting machine")
            try await MachineBootstrapper.bootAndInitialize(id: id)
        }

        await refresh()
    }

    /// Mirrors the CLI's machine-name derivation from an image reference, sanitized
    /// to satisfy machine naming rules (lowercase letters, digits, and hyphens).
    static func derivedName(fromImage image: String) -> String {
        var base = image
        if let reference = try? Reference.parse(image) {
            reference.normalize()
            let imageName = reference.name.components(separatedBy: "/").last ?? "machine"
            let suffix = reference.tag ?? reference.digest ?? "latest"
            base = "\(imageName)-\(suffix)"
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let sanitized = String(base.lowercased().map { allowed.contains($0) ? $0 : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return sanitized.isEmpty ? "machine" : sanitized
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
