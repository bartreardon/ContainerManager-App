//
//  ContainerAgent.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerizationOCI
import Foundation

/// Where container keeps its data, as last reported by the running services.
enum ContainerPaths {
    private static let appRootKey = "lastKnownContainerAppRoot"

    static func observe(health: SystemHealth) {
        UserDefaults.standard.set(health.appRoot.path(percentEncoded: false), forKey: appRootKey)
    }

    static var appRoot: URL {
        if let path = UserDefaults.standard.string(forKey: appRootKey) {
            return URL(filePath: path)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/com.apple.container")
    }
}

/// Which copy of container's in-VM agent (vminit) a container runs.
///
/// A container keeps the agent it was created with — its bundle records the snapshot of
/// the vminit image used, keyed by that image's linux/arm64 manifest digest. Agents
/// before containerization 0.43.0 can't reclaim space (they trim outside the container),
/// so those containers are offered Re-create instead.
enum ContainerAgent {
    static let minimumReclaimVersion = (0, 43, 0)

    /// What the app needs from a container's `runtime-configuration.json`.
    struct RuntimeConfigurationExcerpt: Decodable {
        struct Filesystem: Decodable { let source: String }
        struct Options: Decodable { let autoRemove: Bool? }
        let initialFilesystem: Filesystem
        let options: Options?
    }

    static func runtimeConfiguration(forContainer id: String) -> RuntimeConfigurationExcerpt? {
        let url = ContainerPaths.appRoot.appending(path: "containers/\(id)/runtime-configuration.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(RuntimeConfigurationExcerpt.self, from: data)
    }

    /// The digest in `…/snapshots/<digest>/snapshot`, or nil if the path isn't that shape.
    static func snapshotDigest(inSource source: String) -> String? {
        let components = source.split(separator: "/")
        guard components.count >= 3, components.last == "snapshot",
            components[components.count - 3] == "snapshots"
        else { return nil }
        let digest = String(components[components.count - 2])
        guard digest.count == 64, digest.allSatisfy(\.isHexDigit) else { return nil }
        return digest
    }

    /// True when `tag` names an agent too old to reclaim space; nil when it isn't a version.
    static func isTooOldToReclaim(tag: String) -> Bool? {
        guard let version = ContainerVersion.parse(tag) else { return nil }
        return version < minimumReclaimVersion
    }

    /// vminit image tags on this Mac, keyed by their linux/arm64 manifest digest.
    static func vminitTagsByDigest() async -> [String: String] {
        guard let images = try? await ClientImage.list() else { return [:] }
        var tags: [String: String] = [:]
        for image in images where image.reference.contains("containerization/vminit:") {
            guard let tag = image.reference.split(separator: ":").last,
                let index = try? await image.index()
            else { continue }
            for manifest in index.manifests
            where manifest.platform?.os == "linux" && manifest.platform?.architecture == "arm64" {
                tags[manifest.digest.replacingOccurrences(of: "sha256:", with: "")] = String(tag)
            }
        }
        return tags
    }

    /// The containers among `ids` known to run an agent that can't reclaim space.
    /// Anything that can't be identified is left out, so it keeps Reclaim Unused Space.
    static func tooOldToReclaim(_ ids: [String]) async -> Set<String> {
        let tags = await vminitTagsByDigest()
        var result: Set<String> = []
        for id in ids {
            guard let source = runtimeConfiguration(forContainer: id)?.initialFilesystem.source,
                let digest = snapshotDigest(inSource: source),
                let tag = tags[digest],
                isTooOldToReclaim(tag: tag) == true
            else { continue }
            result.insert(id)
        }
        return result
    }
}
