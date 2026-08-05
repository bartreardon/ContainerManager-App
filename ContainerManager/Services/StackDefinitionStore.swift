//
//  StackDefinitionStore.swift
//  ContainerManager
//

import Foundation

/// The definition a stack was created from, kept so its services can be re-created
/// later without re-entering everything.
struct StackDefinition: Codable {
    var document: StackTemplateDocument
    /// The field values entered at create time — for a compose import, the ones that
    /// came from its `.env`.
    var values: [String: String]

    /// The stack as defined, with field values substituted. Nil if the definition no
    /// longer resolves (e.g. it was hand-edited into an invalid state).
    func plan() -> StackSpec? {
        try? document.toTemplateDef().build(values)
    }
}

/// Stores stack definitions under
/// `~/Library/Application Support/ContainerManager/StackDefinitions/<stack>.json`.
///
/// These files can contain credentials, since a compose import's `${VAR}` fields are
/// commonly filled from a `.env`. They're written owner-read-only and removed when the
/// stack is deleted. The same values are already visible in plain text in the
/// containers' own configuration (`container inspect`), so this doesn't expose anything
/// new while the stack exists — but it is why they're cleaned up with it.
enum StackDefinitionStore {
    private static func root() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory =
            base
            .appendingPathComponent("ContainerManager", isDirectory: true)
            .appendingPathComponent("StackDefinitions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        return directory
    }

    private static func url(for stackName: String) throws -> URL {
        try root().appendingPathComponent("\(stackName).json")
    }

    static func save(_ definition: StackDefinition, for stackName: String) {
        guard
            let url = try? url(for: stackName),
            let data = try? JSONEncoder().encode(definition)
        else { return }
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    static func load(for stackName: String) -> StackDefinition? {
        guard
            let url = try? url(for: stackName),
            let data = try? Data(contentsOf: url)
        else { return nil }
        return try? JSONDecoder().decode(StackDefinition.self, from: data)
    }

    static func delete(for stackName: String) {
        guard let url = try? url(for: stackName) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
