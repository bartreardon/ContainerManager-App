//
//  BuildLibrary.swift
//  ContainerManager
//

import AppKit
import Foundation

/// Manages the on-disk library of Dockerfile build configs under
/// `~/Library/Application Support/ContainerManager/Builds/<name>/`.
///
/// Each build is a folder holding a `Dockerfile` (plus any files the user drops in).
/// The folder doubles as the build context, so `COPY`/`ADD` resolve against it. Users
/// can hand-manage a build by revealing its folder in Finder.
enum BuildLibrary {
    static let dockerfileName = "Dockerfile"

    /// `~/Library/Application Support/ContainerManager/Builds`, created on first use.
    static func root() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir =
            base
            .appendingPathComponent("ContainerManager", isDirectory: true)
            .appendingPathComponent("Builds", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Names of saved builds — subfolders that contain a `Dockerfile` — sorted.
    static func list() -> [String] {
        guard
            let root = try? root(),
            let entries = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey]
            )
        else { return [] }
        return
            entries
            .filter {
                FileManager.default.fileExists(
                    atPath: $0.appendingPathComponent(dockerfileName).path)
            }
            .map { $0.lastPathComponent }
            .sorted()
    }

    /// The build's folder (created if needed). This is the build context.
    static func directory(for name: String) throws -> URL {
        let dir = try root().appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func dockerfileURL(for name: String) throws -> URL {
        try directory(for: name).appendingPathComponent(dockerfileName)
    }

    /// The saved Dockerfile contents, or "" if the build doesn't exist yet.
    static func loadDockerfile(_ name: String) -> String {
        guard
            let url = try? dockerfileURL(for: name),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    static func saveDockerfile(_ name: String, contents: String) throws {
        let url = try dockerfileURL(for: name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    static func delete(_ name: String) throws {
        try FileManager.default.removeItem(at: directory(for: name))
    }

    /// Opens the build's folder in Finder so the user can hand-manage it.
    @MainActor
    static func reveal(_ name: String) {
        guard let dir = try? directory(for: name) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
