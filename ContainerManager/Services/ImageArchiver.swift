//
//  ImageArchiver.swift
//  ContainerManager
//

import Foundation

/// Saves and loads images as OCI archives, via `container image save` / `image load`.
///
/// Unlike ``ContainerExporter``, which writes a container's flat filesystem and can't be
/// read back, this round-trips: an archive keeps the layers and image configuration, so
/// a loaded image is the same image. That makes it the way to move an image between
/// Macs, or to keep one that isn't in a registry.
enum ImageArchiver {
    struct ArchiveError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Writes one or more image references to `destination` as an OCI archive.
    static func save(
        references: [String], to destination: URL, onLine: ((String) -> Void)? = nil
    ) async throws {
        guard !references.isEmpty else { return }
        let result = try await CLIRunner.run(
            ["image", "save", "--output", destination.path] + references, onLine: onLine)
        guard result.exitCode == 0 else {
            throw ArchiveError(
                message: "container image save exited with code \(result.exitCode).\n\(result.output)")
        }
    }

    /// Loads every image in an OCI archive.
    static func load(from source: URL, onLine: ((String) -> Void)? = nil) async throws {
        let result = try await CLIRunner.run(
            ["image", "load", "--input", source.path], onLine: onLine)
        guard result.exitCode == 0 else {
            throw ArchiveError(
                message: "container image load exited with code \(result.exitCode).\n\(result.output)")
        }
    }
}
