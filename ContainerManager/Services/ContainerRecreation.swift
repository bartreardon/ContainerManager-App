//
//  ContainerRecreation.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import ContainerizationError
import ContainerizationOCI
import Foundation

/// Rebuilds a container from its own configuration, so it picks up the current version
/// of container's in-VM agent. Named volumes and binds are re-attached untouched; only
/// what was written elsewhere in the container is lost.
enum ContainerRecreation {
    struct Plan {
        let spec: ContainerCreateSpec
        /// Settings the container has that the create path can't set, so the user can be
        /// told before anything is removed.
        let notCarried: [String]
    }

    struct RemovedButNotRecreated: LocalizedError {
        let containerID: String
        let settings: String
        let underlying: String

        var errorDescription: String? {
            """
            “\(containerID)” was removed but couldn't be created again: \(underlying)

            Its named volumes still have their data. These were its settings:
            \(settings)
            """
        }
    }

    /// An exact create spec for `container`. The entrypoint and arguments are set
    /// separately — the runtime appends arguments to the image's ENTRYPOINT, so passing
    /// the whole command line back would repeat it.
    static func plan(for container: ContainerSnapshot, autoRemove: Bool) -> Plan {
        let configuration = container.configuration
        let process = configuration.initProcess
        var notCarried: [String] = []

        var volumes: [String] = []
        var tmpfs: [String] = []
        for mount in configuration.mounts {
            let readOnly = mount.options.readonly ? ":ro" : ""
            if mount.isTmpfs {
                let options = mount.options.filter { !$0.isEmpty }
                tmpfs.append(options.isEmpty ? mount.destination : "\(mount.destination):\(options.joined(separator: ","))")
            } else if mount.isVolume, let name = mount.volumeName {
                volumes.append("\(name):\(mount.destination)\(readOnly)")
            } else if mount.isVirtiofs, mount.source.hasPrefix("/") {
                volumes.append("\(mount.source):\(mount.destination)\(readOnly)")
            } else {
                notCarried.append("the mount at \(mount.destination)")
            }
        }

        if !configuration.sysctls.isEmpty { notCarried.append("kernel parameters (sysctls)") }
        if !configuration.publishedSockets.isEmpty { notCarried.append("published sockets") }
        if configuration.shmSize != nil { notCarried.append("the shared memory size") }
        // The stop signal isn't listed: it comes from the image, which is used again.
        if configuration.maskedPaths != nil || configuration.readonlyPaths != nil {
            notCarried.append("masked and read-only paths")
        }
        if !process.rlimits.isEmpty { notCarried.append("resource limits (ulimits)") }
        if !process.supplementalGroups.isEmpty { notCarried.append("supplementary groups") }
        if configuration.networks.count > 1 { notCarried.append("networks after the first") }

        let user = process.user.description
        let spec = ContainerCreateSpec(
            name: container.id,
            image: configuration.image.reference,
            command: "",
            env: process.environment,
            cpus: Int64(configuration.resources.cpus),
            memory: ContainerServiceSpec.memorySpec(configuration.resources),
            network: configuration.networks.first?.network ?? NetworkClient.defaultNetworkName,
            publishPorts: configuration.publishedPorts.map(portSpec),
            volumes: volumes,
            labels: configuration.labels.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" },
            platform: "\(configuration.platform.os)/\(configuration.platform.architecture)",
            autoRemove: autoRemove,
            startAfterCreate: false,
            advanced: ContainerAdvancedSettings(
                entrypoint: process.executable.isEmpty ? nil : process.executable,
                arguments: process.arguments,
                workingDirectory: process.workingDirectory.isEmpty ? nil : process.workingDirectory,
                user: user.isEmpty ? nil : user,
                tty: process.terminal,
                tmpfs: tmpfs,
                readOnly: configuration.readOnly,
                useInit: configuration.useInit,
                rosetta: configuration.rosetta,
                ssh: configuration.ssh,
                virtualization: configuration.virtualization,
                capAdd: configuration.capAdd,
                capDrop: configuration.capDrop))
        return Plan(spec: spec, notCarried: notCarried)
    }

    /// "[address:]host[-end]:container[-end]/proto", the form `--publish` takes.
    static func portSpec(_ port: PublishPort) -> String {
        let span = port.count > 1 ? port.count - 1 : 0
        let hostPorts = span > 0 ? "\(port.hostPort)-\(port.hostPort + span)" : "\(port.hostPort)"
        let containerPorts = span > 0 ? "\(port.containerPort)-\(port.containerPort + span)" : "\(port.containerPort)"
        let host = "\(port.hostAddress)"
        let address =
            (host.isEmpty || host == "0.0.0.0") ? "" : host.contains(":") ? "[\(host)]:" : "\(host):"
        return "\(address)\(hostPorts):\(containerPorts)/\(port.proto.rawValue)"
    }

    /// Stops and removes `container`, then creates it again from the same settings and
    /// starts it if it was running. The image is fetched first, so a pull failure leaves
    /// the original in place. `environmentUpdates` ("KEY=value") replace matching entries,
    /// for a stack service whose dependencies have moved; nothing else changes.
    static func recreate(
        _ container: ContainerSnapshot, environmentUpdates: [String] = [], progress: GuiProgress
    ) async throws {
        let autoRemove = ContainerAgent.runtimeConfiguration(forContainer: container.id)?.options?.autoRemove ?? false
        var plan = plan(for: container, autoRemove: autoRemove)
        if !environmentUpdates.isEmpty {
            var spec = plan.spec
            spec.env = ContainerServiceSpec.applying(environmentUpdates, to: spec.env)
            plan = Plan(spec: spec, notCarried: plan.notCarried)
        }
        let wasRunning = container.status == .running

        await progress.setPhase("Fetching \(plan.spec.image)")
        let systemConfig = try await ConfigurationLoader.load()
        _ = try await ClientImage.fetch(
            reference: plan.spec.image, containerSystemConfig: systemConfig, progressUpdate: progress.handler)

        await progress.setPhase("Removing the old container")
        let client = ContainerClient()
        if wasRunning { try? await client.stop(id: container.id) }
        try await client.delete(id: container.id, force: true)

        do {
            try await ContainerLauncher.create(spec: plan.spec, progress: progress, start: wasRunning)
        } catch {
            throw RemovedButNotRecreated(
                containerID: container.id, settings: summary(plan.spec),
                underlying: PresentedError.describe(error))
        }
    }

    /// What the confirmation says before anything is removed.
    static func confirmationMessage(for container: ContainerSnapshot) -> String {
        let plan = plan(for: container, autoRemove: false)
        var message =
            "It's rebuilt from the same image and settings with the current version of container"
            + (container.status == .running ? ", then started again." : ".")
            + " Named volumes and folders shared from your Mac keep their data; anything written"
            + " elsewhere in the container is lost."
        if !plan.notCarried.isEmpty {
            message += "\n\nNot carried over: \(plan.notCarried.joined(separator: ", "))."
        }
        return message
    }

    /// Enough to rebuild the container by hand if re-creating it failed half way.
    static func summary(_ spec: ContainerCreateSpec) -> String {
        var lines = ["image: \(spec.image)"]
        if let entrypoint = spec.advanced.entrypoint { lines.append("entrypoint: \(entrypoint)") }
        if let arguments = spec.advanced.arguments, !arguments.isEmpty {
            lines.append("arguments: \(ShellWords.join(arguments))")
        }
        if !spec.publishPorts.isEmpty { lines.append("ports: \(spec.publishPorts.joined(separator: ", "))") }
        if !spec.volumes.isEmpty { lines.append("volumes: \(spec.volumes.joined(separator: ", "))") }
        lines.append("network: \(spec.network)")
        if !spec.env.isEmpty { lines.append("environment: \(spec.env.joined(separator: " "))") }
        return lines.joined(separator: "\n")
    }
}
