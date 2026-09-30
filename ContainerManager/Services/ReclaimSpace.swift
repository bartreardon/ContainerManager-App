//
//  ReclaimSpace.swift
//  ContainerManager
//

import ContainerAPIClient
import Foundation

/// `container clean`: trims a running container's writable filesystems so the Mac gets
/// back the space deleted files were holding.
///
/// A container keeps the copy of container's in-VM agent it was created with. Agents
/// older than container 1.4.1 run the trim outside the container, where its root can't
/// be trimmed and its volumes don't exist — so a container created before the upgrade
/// fails with "trim failed" and "failed to stat path" until it's re-created.
enum ReclaimSpace {
    struct NeedsRecreating: LocalizedError {
        let containerID: String
        let details: String

        var errorDescription: String? {
            """
            “\(containerID)” was most likely created before container 1.4.1. Containers keep \
            the version of container's in-VM agent they were created with, and older ones \
            can't reclaim space. Re-create the container to update it; its named volumes keep \
            their data.

            Details: \(details)
            """
        }
    }

    static func clean(id: String) async throws {
        do {
            try await ContainerClient().clean(id: id)
        } catch {
            let details = PresentedError.describe(error)
            guard isFromOlderAgent(String(describing: error)) else { throw error }
            throw NeedsRecreating(containerID: id, details: details)
        }
    }

    /// The two failures an agent from before container 1.4.1 gives: the container's root
    /// isn't trimmable from where it runs, and its volume paths don't exist there.
    nonisolated static func isFromOlderAgent(_ description: String) -> Bool {
        description.contains("failed to stat path") || description.contains("trim failed")
    }
}
