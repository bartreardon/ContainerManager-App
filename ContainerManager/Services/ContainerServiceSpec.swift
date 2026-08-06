//
//  ContainerServiceSpec.swift
//  ContainerManager
//

import ContainerResource
import Foundation
import struct ContainerizationOCI.Platform

/// Reads a running container back into the spec that would re-create it.
///
/// Used wherever a container has to be rebuilt in place — repairing a service, or
/// updating the addresses it was given — so that everything not being deliberately
/// changed is carried over exactly as it is, including edits made by hand since the
/// stack was created.
enum ContainerServiceSpec {
    static func spec(from container: ContainerSnapshot, key: String, displayName: String? = nil) -> StackServiceSpec {
        let configuration = container.configuration
        return StackServiceSpec(
            key: key,
            displayName: displayName ?? key,
            image: configuration.image.reference,
            env: configuration.initProcess.environment,
            volumes: configuration.mounts.compactMap(mountSpec),
            publishPorts: configuration.publishedPorts.map(portSpec),
            command: commandLine(configuration.initProcess),
            platform: "\(configuration.platform.os)/\(configuration.platform.architecture)"
        )
    }

    /// The runtime stores the executable separately from its arguments, so joining only
    /// `arguments` drops argv[0]: `sh -c "…"` becomes `-c "…"`, which won't start.
    static func commandLine(_ process: ProcessConfiguration) -> String {
        var argv = process.arguments
        if !process.executable.isEmpty, argv.first != process.executable {
            argv.insert(process.executable, at: 0)
        }
        return ShellWords.join(argv)
    }

    static func portSpec(_ port: PublishPort) -> String {
        let host = "\(port.hostAddress)"
        let mapping = "\(port.hostPort):\(port.containerPort)"
        return (host.isEmpty || host == "0.0.0.0") ? mapping : "\(host):\(mapping)"
    }

    /// Named volumes and host binds, in the "source:destination[:ro]" form the create
    /// path expects. Other mount kinds (the image's own filesystem) are skipped.
    static func mountSpec(_ mount: Filesystem) -> String? {
        let source = mount.volumeName ?? mount.source
        guard mount.isVolume || source.hasPrefix("/") else { return nil }
        guard !source.isEmpty, !mount.destination.isEmpty else { return nil }
        return mount.options.readonly ? "\(source):\(mount.destination):ro" : "\(source):\(mount.destination)"
    }

    /// Replaces entries in `env` with `updates`, matched on the `KEY=` part, leaving
    /// everything else untouched.
    static func applying(_ updates: [String], to env: [String]) -> [String] {
        var result = env
        for entry in updates {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            let key = String(entry[..<separator]) + "="
            if let index = result.firstIndex(where: { $0.hasPrefix(key) }) {
                result[index] = entry
            } else {
                result.append(entry)
            }
        }
        return result
    }
}
