//
//  ContainerCommitter.swift
//  ContainerManager
//

import ContainerResource
import ContainerizationOCI
import Foundation

/// Saves a container's filesystem as a new local image, via `container commit` (1.6.0+).
///
/// Shelled out rather than done in-process: the client libraries have no commit call.
/// The CLI assembles it from an export of the root filesystem, an OCI archive it builds
/// with internal types, and an image load.
///
/// A running container keeps running. Its root filesystem is frozen while its disk is
/// copied, so writes inside it wait for a moment. Only the root filesystem is captured:
/// volumes, folders shared from the Mac and tmpfs mounts aren't. The image takes its
/// command, environment, working directory, user and labels from the container.
enum ContainerCommitter {
    struct CommitError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Tooltip for Commit to Image… while the services predate `container commit`.
    static let needsNewerServices = "Needs container 1.6 or later"

    /// `container commit` only works on a running or stopped container.
    nonisolated static func canCommit(_ status: RuntimeStatus) -> Bool {
        status == .running || status == .stopped
    }

    /// The reference the commit sheet suggests: `local/<name>:latest`, the same shape as
    /// an image built in the app. Container names allow capitals, dots and underscores
    /// where an image name doesn't, so each run of anything but lowercase letters and
    /// digits becomes one hyphen (the reference parser rejects "--").
    nonisolated static func defaultReference(forContainer id: String) -> String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789")
        let name = id.lowercased()
            .split(whereSeparator: { !allowed.contains($0) })
            .joined(separator: "-")
        return "local/\(name.isEmpty ? "container" : name):latest"
    }

    /// True when `reference` parses as an image reference. It still needs the registry
    /// filled in (see `ClientImage.normalizeReference`), which the CLI does.
    nonisolated static func isValidReference(_ reference: String) -> Bool {
        guard !reference.isEmpty else { return false }
        return (try? Reference.parse(reference)) != nil
    }

    /// The image the CLI says it made: it prints the normalized reference last, after
    /// any progress lines.
    nonisolated static func committedReference(fromOutput output: String) -> String? {
        guard
            let last = output.split(whereSeparator: \.isNewline)
                .map({ $0.trimmingCharacters(in: .whitespaces) })
                .last(where: { !$0.isEmpty }),
            !last.contains(" "), isValidReference(last)
        else { return nil }
        return last
    }

    /// Commits container `id` to `reference`, streaming the CLI's output to `onLine`.
    /// Returns the reference the image was stored under.
    static func commit(
        id: String, reference: String, onLine: ((String) -> Void)? = nil
    ) async throws -> String {
        let result = try await CLIRunner.run(["commit", id, reference], onLine: onLine)
        guard result.exitCode == 0 else {
            throw CommitError(
                message: "container commit exited with code \(result.exitCode).\n\(result.output)")
        }
        return committedReference(fromOutput: result.output) ?? reference
    }
}
