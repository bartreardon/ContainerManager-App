//
//  ComposeImporter.swift
//  ContainerManager
//

import Foundation
import Yams

/// Best-effort conversion of a docker-compose YAML file into a stack-definition
/// document.
///
/// Supported per service: `image` (required), `environment` (map or list),
/// `ports` (string forms), `volumes` (string forms; relative host paths are
/// resolved against the compose file's folder), `depends_on` (start order).
/// References to another service by name in env values (`db` or `db:3306`) are
/// rewritten to the runtime `${IP:key}` token our orchestrator substitutes.
/// Everything else is skipped and collected into `document.notes` so the import
/// isn't silently lossy.
enum ComposeImporter {
    enum ComposeError: LocalizedError {
        case notCompose
        case noServices
        case missingImage(String)
        case nothingImportable
        case dependencyCycle

        var errorDescription: String? {
            switch self {
            case .notCompose: "This doesn’t look like a docker-compose file."
            case .noServices: "The compose file has no services."
            case .missingImage(let service):
                "Service “\(service)” has no image and no build — there’s nothing to run."
            case .nothingImportable:
                "None of the services could be imported — they all use compose `build:`, which isn’t supported. Build the image first (Images ▸ Build Image…), then reference it with `image:`."
            case .dependencyCycle: "The services’ depends_on relationships form a cycle."
            }
        }
    }

    static let supportedServiceKeys: Set<String> = [
        "image", "environment", "ports", "volumes", "depends_on", "container_name",
    ]

    static func document(at url: URL) throws -> StackTemplateDocument {
        guard
            let yaml = try Yams.load(yaml: String(contentsOf: url, encoding: .utf8)),
            let top = yaml as? [String: Any]
        else { throw ComposeError.notCompose }
        guard let services = top["services"] as? [String: Any], !services.isEmpty else {
            throw ComposeError.noServices
        }

        var ignored: Set<String> = Set(top.keys.filter { !["services", "version", "name", "volumes", "networks"].contains($0) }.map { "\($0):" })
        let serviceKeys = Set(services.keys)
        let baseName = url.deletingPathExtension().lastPathComponent.sanitizedResourceName

        var specs: [StackTemplateDocument.Service] = []
        var dependencies: [String: [String]] = [:]

        for (key, raw) in services.sorted(by: { $0.key < $1.key }) {
            guard let service = raw as? [String: Any] else { continue }
            guard let image = service["image"] as? String else {
                // A `build:` service can't be represented — skip it and report, rather
                // than failing the whole import (other services may be fine).
                if service["build"] != nil {
                    ignored.insert("\(key) (build:)")
                    continue
                }
                throw ComposeError.missingImage(key)
            }
            for unsupported in service.keys where !supportedServiceKeys.contains(unsupported) {
                ignored.insert("\(key).\(unsupported):")
            }

            let env = environment(service["environment"]).map {
                rewriteServiceReferences(in: $0, services: serviceKeys)
            }
            let (volumeSpecs, skippedAnonymous) = volumeStrings(service["volumes"])
            if skippedAnonymous { ignored.insert("\(key) anonymous volume") }
            let volumes = volumeSpecs.compactMap {
                resolveVolume($0, relativeTo: url.deletingLastPathComponent())
            }
            let ports = portStrings(service["ports"])
            dependencies[key] = dependsOn(service["depends_on"])

            specs.append(
                StackTemplateDocument.Service(
                    key: key,
                    displayName: key,
                    image: image,
                    env: env.isEmpty ? nil : env,
                    volumes: volumes.isEmpty ? nil : volumes,
                    publishPorts: ports.isEmpty ? nil : ports
                ))
        }

        guard !specs.isEmpty else { throw ComposeError.nothingImportable }

        specs = try sortedByDependencies(specs, dependencies: dependencies)

        // First published "host:container" port on the last-started service that has
        // one → the web "Open in Browser" affordance.
        var web: StackTemplateDocument.Web?
        var webPortDefault: String?
        for service in specs.reversed() {
            if let hostPort = service.publishPorts?.first?.split(separator: ":").first.map(String.init),
                Int(hostPort) != nil {
                web = StackTemplateDocument.Web(serviceKey: service.key, portField: "port")
                webPortDefault = hostPort
                break
            }
        }
        // The web port stays a template field so each deployment can pick its own;
        // the published mapping is rewritten to reference it.
        if let web, let webPortDefault {
            specs = specs.map { service in
                var service = service
                if service.key == web.serviceKey, var ports = service.publishPorts, !ports.isEmpty {
                    let container = ports[0].split(separator: ":").dropFirst().joined(separator: ":")
                    ports[0] = "${port}:\(container)"
                    service.publishPorts = ports
                }
                return service
            }
            _ = webPortDefault
        }

        var fields = [
            StackTemplateDocument.Field(key: "name", label: "Stack name", placeholder: baseName, default: baseName)
        ]
        if web != nil {
            fields.append(
                StackTemplateDocument.Field(key: "port", label: "Web port", placeholder: webPortDefault, default: webPortDefault, kind: "port"))
        }

        var notes = "Imported from \(url.lastPathComponent)."
        if !ignored.isEmpty {
            notes += " Not imported: \(ignored.sorted().joined(separator: ", "))."
        }

        return StackTemplateDocument(
            version: StackTemplateDocument.currentVersion,
            id: baseName,
            name: baseName,
            summary: "Imported from \(url.lastPathComponent)",
            systemImage: "square.stack.3d.up",
            notes: notes,
            fields: fields,
            services: specs,
            web: web
        )
    }

    /// Human-readable summary of what didn't carry over, for the post-import alert.
    static func caveats(in document: StackTemplateDocument) -> String? {
        guard let notes = document.notes, notes.contains("Not imported:") else { return nil }
        return notes
    }

    // MARK: Helpers

    /// Compose `environment` is either a map or a list of KEY=value strings.
    private static func environment(_ raw: Any?) -> [String] {
        if let map = raw as? [String: Any] {
            return map.map { "\($0.key)=\($0.value)" }.sorted()
        }
        return stringList(raw)
    }

    private static func stringList(_ raw: Any?) -> [String] {
        (raw as? [Any])?.map { "\($0)" } ?? []
    }

    /// `volumes` entries: short-form strings, or long-form dicts
    /// (`{type, source, target, read_only}`). Anonymous volumes (a target with no
    /// source) can't be represented; they're skipped and flagged (`skippedAnonymous`).
    private static func volumeStrings(_ raw: Any?) -> (specs: [String], skippedAnonymous: Bool) {
        guard let list = raw as? [Any] else { return ([], false) }
        var specs: [String] = []
        var skipped = false
        for item in list {
            if let string = item as? String {
                specs.append(string)
            } else if let dict = item as? [String: Any], let target = dict["target"] as? String {
                if let source = dict["source"] as? String {
                    let readOnly = (dict["read_only"] as? Bool) == true ? ":ro" : ""
                    specs.append("\(source):\(target)\(readOnly)")
                } else {
                    skipped = true
                }
            } else {
                skipped = true
            }
        }
        return (specs, skipped)
    }

    /// `ports` entries: short-form strings, or long-form dicts (`{target, published}`).
    private static func portStrings(_ raw: Any?) -> [String] {
        guard let list = raw as? [Any] else { return [] }
        return list.compactMap { item in
            if let string = item as? String { return string }
            if let dict = item as? [String: Any], let target = dict["target"] {
                if let published = dict["published"] { return "\(published):\(target)" }
                return "\(target)"
            }
            return nil
        }
    }

    /// `depends_on` is either a list of names or a map keyed by service name.
    private static func dependsOn(_ raw: Any?) -> [String] {
        if let list = raw as? [Any] { return list.map { "\($0)" } }
        if let map = raw as? [String: Any] { return Array(map.keys) }
        return []
    }

    /// Rewrites `VAR=db` / `VAR=db:3306` (and `…@db:…` URL hosts) to `${IP:db}` tokens.
    private static func rewriteServiceReferences(in envEntry: String, services: Set<String>) -> String {
        guard let eq = envEntry.firstIndex(of: "=") else { return envEntry }
        let key = envEntry[..<eq]
        var value = String(envEntry[envEntry.index(after: eq)...])
        for service in services {
            if value == service {
                value = StackToken.ip(service)
            } else if value.hasPrefix("\(service):"), Int(value.dropFirst(service.count + 1).prefix(while: \.isNumber)) != nil {
                value = StackToken.ip(service) + value.dropFirst(service.count)
            } else {
                value = value.replacingOccurrences(of: "@\(service):", with: "@\(StackToken.ip(service)):")
                    .replacingOccurrences(of: "//\(service):", with: "//\(StackToken.ip(service)):")
            }
        }
        return "\(key)=\(value)"
    }

    /// Named volumes pass through; relative host paths are made absolute against the
    /// compose file's folder (matching compose semantics).
    private static func resolveVolume(_ entry: String, relativeTo base: URL) -> String? {
        guard entry.hasPrefix("./") || entry.hasPrefix("../") else { return entry }
        let parts = entry.split(separator: ":", maxSplits: 1)
        guard parts.count == 2 else { return entry }
        let host = base.appendingPathComponent(String(parts[0])).standardizedFileURL.path
        return "\(host):\(parts[1])"
    }

    /// Topological sort so `depends_on` services start first (stable for independents).
    private static func sortedByDependencies(
        _ services: [StackTemplateDocument.Service],
        dependencies: [String: [String]]
    ) throws -> [StackTemplateDocument.Service] {
        var sorted: [StackTemplateDocument.Service] = []
        var visiting: Set<String> = []
        var done: Set<String> = []
        let byKey = Dictionary(uniqueKeysWithValues: services.map { ($0.key, $0) })

        func visit(_ key: String) throws {
            guard !done.contains(key), let service = byKey[key] else { return }
            guard visiting.insert(key).inserted else { throw ComposeError.dependencyCycle }
            for dep in dependencies[key] ?? [] { try visit(dep) }
            visiting.remove(key)
            done.insert(key)
            sorted.append(service)
        }

        for service in services.sorted(by: { $0.key < $1.key }) {
            try visit(service.key)
        }
        return sorted
    }
}
