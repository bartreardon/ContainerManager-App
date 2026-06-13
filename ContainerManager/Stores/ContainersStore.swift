//
//  ContainersStore.swift
//  ContainerManager
//

import ArgumentParser
import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import ContainerizationError
import Foundation
import Logging
import Observation
import struct Containerization.Kernel

struct ContainerCreateSpec {
    var name: String
    var image: String
    /// Whitespace-tokenized into process arguments; empty uses the image default.
    var command: String
    /// KEY=VALUE entries.
    var env: [String]
    var cpus: Int64?
    var memory: String?
    /// "[host-ip:]host-port:container-port[/protocol]" entries.
    var publishPorts: [String]
    var autoRemove: Bool
    var startAfterCreate: Bool
}

@Observable
final class ContainersStore {
    private(set) var containers: [ContainerSnapshot] = []
    private(set) var busyIds: Set<String> = []
    var lastError: PresentedError?

    private var cachedConfig: ContainerSystemConfig?

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

    /// Creates a container following the same pipeline as `container run`:
    /// fetch + unpack the image, resolve kernel and init image, create, then
    /// optionally start detached. Throws so the create sheet can surface failures.
    func create(spec: ContainerCreateSpec, progress: GuiProgress) async throws {
        let systemConfig = try await self.systemConfig()
        let client = ContainerClient()

        let name = spec.name.isEmpty ? nil : spec.name
        let id = Utility.createContainerID(name: name)
        try Utility.validEntityName(id)

        guard (try? await client.get(id: id)) == nil else {
            throw ContainerizationError(.exists, message: "a container named “\(id)” already exists")
        }

        // ArgumentParser-backed flags must come from parse([]); bare init() traps on read.
        var management = try Flags.Management.parse([])
        management.name = name
        management.networks = []  // default network; picker arrives with the networks feature
        management.publishPorts = spec.publishPorts
        management.remove = spec.autoRemove

        var processFlags = try Flags.Process.parse([])
        processFlags.env = spec.env

        let arguments = spec.command
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)

        let configuration: ContainerConfiguration
        let kernel: Kernel
        let initImage: String?
        do {
            (configuration, kernel, initImage) = try await Utility.containerConfigFromFlags(
                id: id,
                image: spec.image,
                arguments: arguments,
                process: processFlags,
                management: management,
                resource: Flags.Resource(cpus: spec.cpus, memory: spec.memory),
                registry: Flags.Registry(scheme: "auto"),
                imageFetch: Flags.ImageFetch(maxConcurrentDownloads: 3),
                containerSystemConfig: systemConfig,
                progressUpdate: progress.handler,
                log: Logger(label: "com.bartreardon.ContainerManager")
            )
        } catch {
            let text = String(describing: error)
            if text.lowercased().contains("kernel") {
                throw ContainerizationError(
                    .internalError,
                    message: "\(text)\n\nHint: no default kernel may be installed. Restart container services from the app, or run `container system kernel set --recommended`."
                )
            }
            throw error
        }

        progress.setPhase("Creating container")
        try await client.create(
            configuration: configuration,
            options: ContainerCreateOptions(autoRemove: spec.autoRemove),
            kernel: kernel,
            initImage: initImage
        )

        if spec.startAfterCreate {
            progress.setPhase("Starting container")
            do {
                try await Self.startDetached(id: id, tty: false, client: client)
            } catch {
                // Mirror the CLI: don't leave a half-started container behind.
                try? await client.delete(id: id)
                throw error
            }
        }

        await refresh()
    }

    func start(id: String) async {
        await perform(id: id, title: "Failed to start container") {
            let client = ContainerClient()
            let container = try await client.get(id: id)
            guard container.status != .running else { return }
            try await Self.startDetached(
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

    private static func startDetached(id: String, tty: Bool, client: ContainerClient) async throws {
        let io = try ProcessIO.create(tty: tty, interactive: false, detach: true)
        defer { try? io.close() }

        var dynamicEnv: [String: String] = [:]
        if let sshAuthSock = ProcessInfo.processInfo.environment["SSH_AUTH_SOCK"] {
            dynamicEnv["SSH_AUTH_SOCK"] = sshAuthSock
        }

        let process = try await client.bootstrap(id: id, stdio: io.stdio, dynamicEnv: dynamicEnv)
        try await process.start()
        try io.closeAfterStart()
    }

    private func systemConfig() async throws -> ContainerSystemConfig {
        if let cachedConfig {
            return cachedConfig
        }
        let config = try await ConfigurationLoader.load()
        cachedConfig = config
        return config
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
