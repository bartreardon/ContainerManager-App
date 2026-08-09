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
        "image", "environment", "ports", "volumes", "depends_on", "command",
        "platform", "mem_limit", "cpus",
    ]

    /// Memory from `mem_limit` (compose v2) or `deploy.resources.limits.memory` (v3),
    /// in the spelling the runtime wants.
    ///
    /// Worth carrying over: the runtime's default is modest, and a service given less
    /// than it needs stops answering rather than failing outright — which is a nasty
    /// way to find out.
    nonisolated static func memoryLimit(_ service: [String: Any]) -> String? {
        if let direct = service["mem_limit"] {
            return normalizedMemory("\(direct)")
        }
        guard
            let deploy = service["deploy"] as? [String: Any],
            let resources = deploy["resources"] as? [String: Any],
            let limits = resources["limits"] as? [String: Any],
            let memory = limits["memory"]
        else { return nil }
        return normalizedMemory("\(memory)")
    }

    /// Compose writes `2g`, `512m` or a byte count; the runtime wants a unit suffix.
    nonisolated static func normalizedMemory(_ raw: String) -> String? {
        let value = raw.trimmingCharacters(in: .whitespaces).lowercased()
        guard !value.isEmpty else { return nil }
        if let bytes = Int64(value) {
            // A bare number is bytes in compose, which the runtime would read as MB.
            return "\(max(1, bytes / (1024 * 1024)))m"
        }
        // 2gb → 2g, 512mb → 512m; anything else is passed through for the runtime to judge.
        if value.hasSuffix("b"), value.count > 1 { return String(value.dropLast()) }
        return value
    }

    nonisolated static func cpuLimit(_ service: [String: Any]) -> Int64? {
        if let direct = service["cpus"], let value = Double("\(direct)"), value > 0 {
            return Int64(value.rounded())
        }
        guard
            let deploy = service["deploy"] as? [String: Any],
            let resources = deploy["resources"] as? [String: Any],
            let limits = resources["limits"] as? [String: Any],
            let cpus = limits["cpus"], let value = Double("\(cpus)"), value > 0
        else { return nil }
        return Int64(value.rounded())
    }

    static func document(at url: URL) throws -> StackTemplateDocument {
        guard
            let yaml = try Yams.load(yaml: String(contentsOf: url, encoding: .utf8)),
            let top = yaml as? [String: Any]
        else { throw ComposeError.notCompose }
        guard let services = top["services"] as? [String: Any], !services.isEmpty else {
            throw ComposeError.noServices
        }

        // Item → why it couldn't be carried over. A bare list of keys leaves you
        // guessing whether each one mattered.
        var ignored: [String: String] = [:]
        for key in top.keys where !["services", "version", "name", "volumes", "networks"].contains(key) {
            ignored["\(key):"] = reason(forKey: key)
        }
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
                    ignored["\(key) (build:)"] =
                        "images must be built first; use Images ▸ Build Image…, then reference the tag with image:"
                    continue
                }
                throw ComposeError.missingImage(key)
            }
            for unsupported in service.keys where !supportedServiceKeys.contains(unsupported) {
                ignored["\(key).\(unsupported):"] = reason(forKey: unsupported)
            }

            let env = environment(service["environment"]).map {
                rewriteServiceReferences(in: $0, services: serviceKeys)
            }
            let (volumeSpecs, skippedAnonymous) = volumeStrings(service["volumes"])
            if skippedAnonymous {
                ignored["\(key) anonymous volume"] =
                    "a mount with no source can't be named; give it a volume name or a host path"
            }
            let volumes = volumeSpecs.compactMap {
                resolveVolume($0, relativeTo: url.deletingLastPathComponent())
            }
            let ports = portStrings(service["ports"])
            dependencies[key] = dependsOn(service["depends_on"])

            let command = commandString(service["command"])

            specs.append(
                StackTemplateDocument.Service(
                    key: key,
                    displayName: key,
                    image: image,
                    env: env.isEmpty ? nil : env,
                    volumes: volumes.isEmpty ? nil : volumes,
                    publishPorts: ports.isEmpty ? nil : ports,
                    command: command.isEmpty ? nil : command,
                    platform: normalizedPlatform(service["platform"]),
                    cpus: cpuLimit(service),
                    memory: memoryLimit(service)
                ))
        }

        guard !specs.isEmpty else { throw ComposeError.nothingImportable }

        specs = try sortedByDependencies(specs, dependencies: dependencies)

        // Compose's `${VAR}` interpolation uses the same syntax as our own template
        // fields, so turn each variable into a field rather than choking on it.
        let variables = extractVariables(in: &specs)
        let envDefaults = envFileDefaults(beside: url)

        // First published port on the last-started service → the "Open in Browser"
        // affordance. In `[host-ip:]host:container[/proto]` the host port is the
        // second-to-last component.
        var web: StackTemplateDocument.Web?
        var webPortDefault: String?
        for service in specs.reversed() {
            guard let published = service.publishPorts?.first else { continue }
            let parts = published.split(separator: ":").map(String.init)
            guard parts.count >= 2 else { continue }
            let hostPort = parts[parts.count - 2]
            if Int(hostPort) != nil {
                web = StackTemplateDocument.Web(serviceKey: service.key, portField: "port")
                webPortDefault = hostPort
                break
            }
            // A `${VAR}` host port already has a field of its own — point at that.
            if hostPort.hasPrefix("${"), hostPort.hasSuffix("}") {
                let name = String(hostPort.dropFirst(2).dropLast())
                if variables[name] != nil {
                    web = StackTemplateDocument.Web(serviceKey: service.key, portField: name)
                    break
                }
            }
        }
        // A literal web port becomes a template field so each deployment can pick its
        // own; the published mapping is rewritten to reference it.
        if let web, web.portField == "port" {
            specs = specs.map { service in
                var service = service
                if service.key == web.serviceKey, var ports = service.publishPorts, !ports.isEmpty {
                    var parts = ports[0].split(separator: ":").map(String.init)
                    parts[parts.count - 2] = "${port}"
                    ports[0] = parts.joined(separator: ":")
                    service.publishPorts = ports
                }
                return service
            }
        }

        var fields = [
            StackTemplateDocument.Field(key: "name", label: "Stack name", placeholder: baseName, default: baseName)
        ]
        if web?.portField == "port" {
            fields.append(
                StackTemplateDocument.Field(key: "port", label: "Web port", placeholder: webPortDefault, default: webPortDefault, kind: "port"))
        }
        for name in variables.keys.sorted() {
            let value = envDefaults[name] ?? variables[name] ?? ""
            fields.append(
                StackTemplateDocument.Field(
                    key: name,
                    label: name,
                    placeholder: value.isEmpty ? nil : value,
                    default: value,
                    kind: isSecret(name) ? "password" : nil
                ))
        }

        var notes = "Imported from \(url.lastPathComponent)."
        if !variables.isEmpty {
            let prefilled = variables.keys.filter { envDefaults[$0] != nil }.count
            if prefilled > 0 {
                notes += " Prefilled \(prefilled) of \(variables.count) variables from the .env beside it."
            } else {
                notes +=
                    " Found \(variables.count) variables with no .env beside the compose file — enter them on the next screen, or use “Import .env…” there."
            }
        }
        if !ignored.isEmpty {
            let entries = ignored.sorted { $0.key < $1.key }.map { "• \($0.key) — \($0.value)" }
            notes += "\n\nNot imported:\n" + entries.joined(separator: "\n")
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

    /// Human-readable summary of what didn't carry over — and how variables were
    /// resolved — for the post-import alert.
    static func caveats(in document: StackTemplateDocument) -> String? {
        guard let notes = document.notes,
            notes.contains("Not imported:") || notes.contains("variables")
        else { return nil }
        return notes
    }

    /// True when the summary reports something that was dropped (as opposed to only
    /// reporting how variables were filled in).
    static func hasLosses(_ summary: String) -> Bool {
        summary.contains("Not imported:")
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

    /// Compose `command:` is either a string (`sh -c "…"`) or an argv list.
    private static func commandString(_ raw: Any?) -> String {
        if let string = raw as? String { return string }
        if let list = raw as? [Any] { return ShellWords.join(list.map { "\($0)" }) }
        return ""
    }

    /// Why a compose key couldn't be carried over. Says what the consequence is, so the
    /// summary is actionable rather than a list of things that were silently dropped.
    private static func reason(forKey key: String) -> String {
        switch key {
        case "restart":
            "restart policies aren't supported; start the stack again if a service stops"
        case "deploy":
            "only resources.limits is read, for CPU and memory; replicas, restart policies and placement aren't supported"
        case "healthcheck":
            "health probes aren't run; dependants wait for the port to accept connections instead"
        case "cap_add", "cap_drop", "privileged", "security_opt":
            "capability and privilege changes aren't supported"
        case "networks", "network_mode", "links", "dns", "extra_hosts":
            "every service shares one stack network and reaches the others by IP"
        case "profiles":
            "profiles aren't evaluated — all services were imported"
        case "env_file":
            "referenced env files aren't read; use “Import .env…” on the create sheet"
        case "extends", "include":
            "composing files together isn't supported; flatten it into this file"
        case "entrypoint":
            "entrypoint overrides aren't supported; fold it into command:"
        case "secrets", "configs":
            "secrets and configs aren't supported; pass values as environment variables"
        case "devices", "sysctls", "ulimits", "userns_mode", "cgroup_parent":
            "host and kernel tuning isn't supported"
        case "logging":
            "logging drivers aren't configurable; output is available from the container"
        case "container_name":
            "containers are named after the stack and the service, so the stack can be created more than once without the names colliding"
        case "user":
            "running as a different user isn't supported"
        case "working_dir":
            "the working directory can't be overridden; set it in the image"
        case "depends_on":
            "only ordering is honoured, not conditions"
        default:
            key.hasPrefix("x-") ? "an extension field, not part of the spec" : "not supported"
        }
    }

    /// Compose `platform:` written in `uname -m` terms (`linux/x86_64`) into the OCI
    /// spelling `container` expects (`linux/amd64`). Apple silicon runs amd64 images
    /// under emulation, so these are worth carrying through rather than dropping.
    private static func normalizedPlatform(_ raw: Any?) -> String? {
        guard let value = (raw as? String)?.trimmingCharacters(in: .whitespaces), !value.isEmpty else {
            return nil
        }
        return
            value
            .replacingOccurrences(of: "x86_64", with: "amd64")
            .replacingOccurrences(of: "aarch64", with: "arm64")
    }

    /// Names that should be entered as passwords rather than plain text.
    private static func isSecret(_ name: String) -> Bool {
        let upper = name.uppercased()
        return ["PASSWORD", "SECRET", "TOKEN", "PRIVATE_KEY"].contains { upper.contains($0) }
    }

    /// Rewrites every `${VAR}` / `${VAR:-default}` found in the services down to
    /// `${VAR}`, and returns the variables discovered with any inline defaults.
    /// `${IP:…}` tokens are ours, generated above, and are left alone.
    private static func extractVariables(
        in specs: inout [StackTemplateDocument.Service]
    ) -> [String: String] {
        var found: [String: String] = [:]

        func rewrite(_ string: String) -> String {
            var result = ""
            var rest = Substring(string)
            while let start = rest.range(of: "${") {
                result += rest[..<start.lowerBound]
                guard let end = rest[start.upperBound...].firstIndex(of: "}") else {
                    return result + rest[start.lowerBound...]
                }
                let token = String(rest[start.upperBound..<end])
                if token.hasPrefix("IP:") {
                    result += "${\(token)}"
                } else {
                    var name = token
                    var fallback = ""
                    if let separator = token.range(of: ":-") {
                        name = String(token[..<separator.lowerBound])
                        fallback = String(token[separator.upperBound...])
                    }
                    if found[name, default: ""].isEmpty { found[name] = fallback }
                    result += "${\(name)}"
                }
                rest = rest[rest.index(after: end)...]
            }
            return result + rest
        }

        specs = specs.map { service in
            var service = service
            service.image = rewrite(service.image)
            service.command = service.command.map(rewrite)
            service.env = service.env?.map(rewrite)
            service.volumes = service.volumes?.map(rewrite)
            service.publishPorts = service.publishPorts?.map(rewrite)
            return service
        }
        return found
    }

    /// Values from a `.env` sitting next to the compose file — the same file compose
    /// itself would interpolate from — used to prefill the generated fields.
    private static func envFileDefaults(beside url: URL) -> [String: String] {
        let envURL = url.deletingLastPathComponent().appendingPathComponent(".env")
        guard let text = try? String(contentsOf: envURL, encoding: .utf8) else { return [:] }
        var values: [String: String] = [:]
        for entry in EnvFile.parse(text) {
            guard let separator = entry.firstIndex(of: "=") else { continue }
            values[String(entry[..<separator])] = String(entry[entry.index(after: separator)...])
        }
        return values
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
