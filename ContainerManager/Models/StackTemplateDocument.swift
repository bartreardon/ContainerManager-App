//
//  StackTemplateDocument.swift
//  ContainerManager
//

import Foundation

/// The on-disk, declarative form of a stack template (`.containerstack`, JSON).
///
/// Strings in `services` may contain two kinds of token:
/// - `${<fieldKey>}` — replaced at create time with the value the user entered for
///   that field (the `name` field is sanitized via `sanitizedResourceName` first).
/// - `${IP:<serviceKey>}` — left untouched here; substituted at *run* time by
///   `StackOrchestrator` with the service's IP.
///
/// The bundled built-in templates use this same format, so any of them can be
/// exported as a working example.
struct StackTemplateDocument: Codable {
    struct Field: Codable {
        var key: String
        var label: String
        var placeholder: String?
        var `default`: String?
        var kind: String?
    }

    struct Service: Codable {
        var key: String
        var displayName: String
        var image: String
        var env: [String]?
        var volumes: [String]?
        var publishPorts: [String]?
    }

    struct Web: Codable {
        var serviceKey: String
        /// Key of the field whose value is the published host port.
        var portField: String
    }

    var version: Int
    var id: String
    var name: String
    var summary: String
    var systemImage: String?
    var notes: String?
    var fields: [Field]
    var services: [Service]
    var web: Web?

    enum DocumentError: LocalizedError {
        case unsupportedVersion(Int)
        case unknownPlaceholder(String)
        case missingNameField
        case badWebPortField(String)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let v):
                "This stack definition uses format version \(v); this version of ContainerManager supports version 1."
            case .unknownPlaceholder(let token):
                "The stack definition references “${\(token)}”, which doesn’t match any of its fields."
            case .missingNameField:
                "The stack definition must include a “name” field."
            case .badWebPortField(let key):
                "web.portField “\(key)” doesn’t match a port field."
            }
        }
    }

    static let currentVersion = 1

    // MARK: Decode / encode

    static func decode(from data: Data) throws -> StackTemplateDocument {
        let document = try JSONDecoder().decode(StackTemplateDocument.self, from: data)
        guard document.version == currentVersion else {
            throw DocumentError.unsupportedVersion(document.version)
        }
        return document
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }

    // MARK: Conversion to the runtime template model

    private var templateFields: [StackTemplateField] {
        fields.map { field in
            StackTemplateField(
                key: field.key,
                label: field.label,
                placeholder: field.placeholder ?? "",
                defaultValue: field.default ?? "",
                kind: fieldKind(field.kind)
            )
        }
    }

    private func fieldKind(_ raw: String?) -> StackTemplateField.Kind {
        switch raw {
        case "password": .password
        case "port": .port
        case "directory": .directory
        default: .text
        }
    }

    /// Bridges the document into the closure-based template model the UI and
    /// orchestrator already consume. The generated closure validates the entered
    /// values (per field kind) and substitutes `${field}` tokens.
    func toTemplateDef() throws -> StackTemplateDef {
        guard fields.contains(where: { $0.key == "name" }) else {
            throw DocumentError.missingNameField
        }
        if let web {
            guard fields.contains(where: { $0.key == web.portField }) else {
                throw DocumentError.badWebPortField(web.portField)
            }
        }
        // Surface unknown placeholders at load/import time (with an empty value set,
        // substitute only checks token validity) rather than mid-create.
        _ = try substitutedServices(with: defaultValues())

        return StackTemplateDef(
            id: id,
            name: name,
            summary: summary,
            systemImage: systemImage ?? "square.stack.3d.up",
            fields: templateFields,
            document: self
        ) { values in
            var resolved: [String: String] = [:]
            for field in templateFields {
                let raw = (values[field.key] ?? "").trimmingCharacters(in: .whitespaces)
                let value = raw.isEmpty ? field.defaultValue : raw
                switch field.kind {
                case .port:
                    guard let port = Int(value), (1...65535).contains(port) else {
                        throw StackTemplateError.invalidPort(value)
                    }
                case .directory:
                    guard !value.isEmpty else { throw StackTemplateError.missing(field.label) }
                case .text, .password:
                    break
                }
                resolved[field.key] = field.key == "name" ? value.sanitizedResourceName : value
            }

            let stackName = resolved["name"] ?? "stack"
            var webPort: Int?
            if let web { webPort = resolved[web.portField].flatMap(Int.init) }

            return StackSpec(
                name: stackName,
                networkName: "\(stackName)-net",
                services: try substitutedServices(with: resolved),
                webServiceKey: web?.serviceKey,
                webPort: webPort
            )
        }
    }

    /// Field defaults keyed by field key (used for import-time validation).
    private func defaultValues() -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.key, $0.default ?? "x") })
    }

    private func substitutedServices(with values: [String: String]) throws -> [StackServiceSpec] {
        try services.map { service in
            StackServiceSpec(
                key: service.key,
                displayName: service.displayName,
                image: try substitute(service.image, values: values),
                env: try (service.env ?? []).map { try substitute($0, values: values) },
                volumes: try (service.volumes ?? []).map { try substitute($0, values: values) },
                publishPorts: try (service.publishPorts ?? []).map { try substitute($0, values: values) }
            )
        }
    }

    /// Replaces `${field}` tokens; leaves runtime `${IP:…}` tokens untouched; throws
    /// on tokens that match neither.
    private func substitute(_ string: String, values: [String: String]) throws -> String {
        var result = ""
        var rest = Substring(string)
        while let start = rest.range(of: "${") {
            result += rest[..<start.lowerBound]
            guard let end = rest[start.upperBound...].firstIndex(of: "}") else {
                // Unterminated token: keep the remainder literally.
                result += rest[start.lowerBound...]
                return result
            }
            let token = String(rest[start.upperBound..<end])
            if token.hasPrefix("IP:") {
                result += "${\(token)}"
            } else if let value = values[token] {
                result += value
            } else {
                throw DocumentError.unknownPlaceholder(token)
            }
            rest = rest[rest.index(after: end)...]
        }
        result += rest
        return result
    }
}
