//
//  ContainerLauncher.swift
//  ContainerManager
//

import ArgumentParser
import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import ContainerizationError
import Foundation
import Logging
import struct Containerization.Kernel

/// Shared container create/start pipeline used by both the Containers section and
/// the stack orchestrator. Mirrors `container run`: fetch + unpack image, resolve
/// kernel and init image, create, and optionally start detached.
enum ContainerLauncher {
    /// Creates a container from a spec and optionally starts it detached.
    /// Returns the container id. On a start-phase failure the partial container is deleted.
    @discardableResult
    static func create(spec: ContainerCreateSpec, progress: GuiProgress, start: Bool) async throws -> String {
        let systemConfig = try await ConfigurationLoader.load()
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
        management.networks = spec.network == NetworkClient.defaultNetworkName ? [] : [spec.network]
        management.publishPorts = spec.publishPorts
        management.volumes = spec.volumes
        management.labels = spec.labels
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

        if start {
            progress.setPhase("Starting container")
            do {
                try await startDetached(id: id, client: client)
            } catch {
                try? await client.delete(id: id)
                throw error
            }
        }

        return id
    }

    /// Starts an already-created container in the background.
    static func startDetached(id: String, tty: Bool = false, client: ContainerClient = ContainerClient()) async throws {
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
}
