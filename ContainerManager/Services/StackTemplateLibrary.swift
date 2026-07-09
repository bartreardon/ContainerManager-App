//
//  StackTemplateLibrary.swift
//  ContainerManager
//

import AppKit
import Foundation
import UniformTypeIdentifiers

extension UTType {
    /// Native stack-definition documents (`.containerstack`, JSON). Declared in Info.plist.
    static let containerstack = UTType(exportedAs: "com.bartreardon.containermanager.containerstack")
}

/// Manages the user's imported stack templates: `.containerstack` documents under
/// `~/Library/Application Support/ContainerManager/StackTemplates/`.
///
/// The folder is the source of truth and the management UI — the list is re-read
/// each time the New Stack menu opens, so dropping a file in (or deleting one in
/// Finder) takes effect immediately.
enum StackTemplateLibrary {
    /// `~/Library/Application Support/ContainerManager/StackTemplates`, created on first use.
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
            .appendingPathComponent("StackTemplates", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// The user's templates, sorted by display name. Files that fail to decode are
    /// skipped (they can be fixed in place and re-read on the next menu open).
    static func list() -> [StackTemplateDef] {
        guard
            let root = try? root(),
            let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return
            entries
            .filter { $0.pathExtension == "containerstack" }
            .compactMap { url in
                guard
                    let data = try? Data(contentsOf: url),
                    let document = try? StackTemplateDocument.decode(from: data),
                    let def = try? document.toTemplateDef()
                else { return nil }
                return def
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Validates and imports a native `.containerstack`/JSON document into the library.
    /// Returns the imported template. Throws with a descriptive error when the file
    /// doesn't decode or its placeholders don't resolve.
    @discardableResult
    static func importDocument(_ document: StackTemplateDocument) throws -> StackTemplateDef {
        var document = document
        // Keep both when the id collides with an existing template (built-in or imported).
        let taken = Set((StackTemplates.all + list()).map(\.id))
        if taken.contains(document.id) {
            var candidate = document.id
            var n = 2
            while taken.contains(candidate) {
                candidate = "\(document.id)-\(n)"
                n += 1
            }
            document.id = candidate
        }

        let def = try document.toTemplateDef()
        let url = try root().appendingPathComponent("\(document.id).containerstack")
        try document.encoded().write(to: url, options: .atomic)
        return def
    }

    /// Imports a stack-definition file: docker-compose YAML is converted on the way in;
    /// anything else is decoded as a native `.containerstack` document.
    @discardableResult
    static func importFile(at url: URL) throws -> StackTemplateDef {
        let document: StackTemplateDocument
        if ["yaml", "yml"].contains(url.pathExtension.lowercased()) {
            document = try ComposeImporter.document(at: url)
        } else {
            document = try StackTemplateDocument.decode(from: try Data(contentsOf: url))
        }
        return try importDocument(document)
    }

    /// Opens the templates folder in Finder (the management UI).
    @MainActor
    static func reveal() {
        guard let dir = try? root() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([dir])
    }
}
