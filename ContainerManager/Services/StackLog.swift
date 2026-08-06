//
//  StackLog.swift
//  ContainerManager
//

import AppKit
import Foundation

/// A per-stack record of how it was built: what the import couldn't carry over, the
/// creation steps, and any failures.
///
/// Creating a stack is a long, one-shot process whose output previously vanished with
/// the sheet — including the "not imported" summary, which appeared once in an alert.
/// That's exactly the information needed afterwards to work out which manual steps are
/// still required, so it's kept on disk next to the stack's definition.
enum StackLog {
    private static func root() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory =
            base
            .appendingPathComponent("ContainerManager", isDirectory: true)
            .appendingPathComponent("StackLogs", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }

    static func url(for stackName: String) throws -> URL {
        try root().appendingPathComponent("\(stackName).log")
    }

    static func exists(for stackName: String) -> Bool {
        guard let url = try? url(for: stackName) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Appends a titled, timestamped section. Empty sections are skipped.
    static func append(section: String, lines: [String], to stackName: String) {
        let body = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !body.isEmpty, let url = try? url(for: stackName) else { return }

        let stamp = Date().formatted(date: .abbreviated, time: .standard)
        let entry = "===== \(stamp) — \(section) =====\n" + body.joined(separator: "\n") + "\n\n"

        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try? (existing + entry).write(to: url, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func read(for stackName: String) -> String {
        guard
            let url = try? url(for: stackName),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else { return "" }
        return text
    }

    static func delete(for stackName: String) {
        guard let url = try? url(for: stackName) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    @MainActor
    static func reveal(_ stackName: String) {
        guard let url = try? url(for: stackName) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
