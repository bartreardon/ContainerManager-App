//
//  ContainerExporter.swift
//  ContainerManager
//

import Foundation

/// Saves a container's filesystem as a tar archive, via `container export`.
///
/// Shelled out rather than done in-process for the same reason as image builds: the
/// CLI streams progress as plain lines, and the archive is written straight to disk.
enum ContainerExporter {
    struct ExportError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Requires container 1.2.1 or later — earlier versions could only export images.
    static func export(id: String, to destination: URL, onLine: ((String) -> Void)? = nil) async throws {
        let result = try await CLIRunner.run(
            ["export", "--output", destination.path, id], onLine: onLine)
        guard result.exitCode == 0 else {
            throw ExportError(
                message: "container export exited with code \(result.exitCode).\n\(result.output)")
        }
    }
}
