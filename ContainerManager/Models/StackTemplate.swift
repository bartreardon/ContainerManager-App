//
//  StackTemplate.swift
//  ContainerManager
//

import Foundation

/// One container within a stack. `env` values may contain `${IP:<key>}` tokens that
/// the orchestrator substitutes with the runtime IP of an earlier service.
struct StackServiceSpec: Identifiable {
    let key: String
    var displayName: String
    var image: String
    var env: [String]
    var volumes: [String]
    var publishPorts: [String]

    var id: String { key }
}

/// A multi-container stack to stand up: a dedicated network plus services started in order.
struct StackSpec {
    var name: String
    var networkName: String
    var services: [StackServiceSpec]
    /// Which service exposes the browser-facing port.
    var webServiceKey: String?
    /// Host port the web service publishes (for the "Open" affordance).
    var webPort: Int?
}

enum StackLabels {
    static let stack = "com.containermanager.stack"
    static let role = "com.containermanager.stack.role"
    static let url = "com.containermanager.stack.url"
}

/// Token used inside service env to reference another service's runtime IP, e.g.
/// `WORDPRESS_DB_HOST=${IP:db}:3306`.
enum StackToken {
    static func ip(_ key: String) -> String { "${IP:\(key)}" }
}

// MARK: - Data-driven templates

/// A single configurable input on a template's create form.
struct StackTemplateField: Identifiable {
    enum Kind {
        case text
        case password
        case port
        case directory
    }

    let key: String
    let label: String
    var placeholder: String = ""
    var defaultValue: String = ""
    var kind: Kind = .text

    var id: String { key }
}

enum StackTemplateError: LocalizedError {
    case missing(String)
    case invalidPort(String)

    var errorDescription: String? {
        switch self {
        case .missing(let label): "\(label) is required."
        case .invalidPort(let value): "“\(value)” is not a valid port number."
        }
    }
}

/// A ready-made stack: the fields its create form shows, and a builder that turns
/// the collected values into a `StackSpec`. Always backed by a declarative
/// `StackTemplateDocument` (bundled or imported), kept for export.
struct StackTemplateDef: Identifiable {
    let id: String
    let name: String
    let summary: String
    let systemImage: String
    let fields: [StackTemplateField]
    var document: StackTemplateDocument?
    let build: ([String: String]) throws -> StackSpec
}

/// Built-in templates, decoded from the `.containerstack` documents bundled with the
/// app (Resources/StackTemplates). The same format users can import and export.
enum StackTemplates {
    /// Menu order for the bundled templates.
    private static let order = [
        "wordpress", "postgres", "postgres-adminer", "mailpit",
        "gitea", "code-server", "nginx-static",
    ]

    static let all: [StackTemplateDef] = load()

    private static func load() -> [StackTemplateDef] {
        let urls = Bundle.main.urls(forResourcesWithExtension: "containerstack", subdirectory: nil) ?? []
        let templates = urls.compactMap { url -> StackTemplateDef? in
            do {
                let document = try StackTemplateDocument.decode(from: try Data(contentsOf: url))
                return try document.toTemplateDef()
            } catch {
                // A bundled template failing to decode is a programmer error.
                assertionFailure("Bundled template \(url.lastPathComponent) failed to load: \(error)")
                return nil
            }
        }
        return templates.sorted {
            (order.firstIndex(of: $0.id) ?? .max, $0.name) < (order.firstIndex(of: $1.id) ?? .max, $1.name)
        }
    }
}
