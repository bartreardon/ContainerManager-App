//
//  StackValidator.swift
//  ContainerManager
//

import Foundation

/// Checks a stack plan before anything is created.
///
/// Stacks are stood up service by service, so a problem in the fourth service is only
/// discovered after the first three are running — leaving a half-built stack behind.
/// Everything here is knowable up front, so it's reported in one go and nothing is
/// created until it's clean.
enum StackValidator {
    struct Issue {
        /// The service the problem belongs to; empty for stack-level problems.
        let service: String
        let message: String

        var described: String { service.isEmpty ? message : "\(service): \(message)" }
    }

    struct Failure: LocalizedError {
        let issues: [Issue]

        var errorDescription: String? {
            issues.count == 1
                ? issues[0].described
                : issues.map { "• \($0.described)" }.joined(separator: "\n")
        }
    }

    /// Every problem detectable without touching the runtime.
    nonisolated static func issues(in spec: StackSpec) -> [Issue] {
        var found: [Issue] = []
        if spec.services.isEmpty {
            found.append(Issue(service: "", message: "The stack has no services."))
        }
        for service in spec.services {
            if service.image.trimmingCharacters(in: .whitespaces).isEmpty {
                found.append(Issue(service: service.key, message: "no image is set"))
            }
            found += service.volumes.flatMap { mountIssues($0, service: service.key) }
            found += service.publishPorts.flatMap { portIssues($0, service: service.key) }
        }
        return found
    }

    /// "source:destination[:options]" — a host source must exist, since the runtime
    /// won't create it and the failure surfaces late and cryptically.
    nonisolated private static func mountIssues(_ mount: String, service: String) -> [Issue] {
        let parts = mount.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2 else {
            return [Issue(service: service, message: "“\(mount)” isn’t a valid mount — expected source:/path")]
        }
        let source = parts[0]
        let destination = parts[1]

        if source.isEmpty {
            return [Issue(service: service, message: "“\(mount)” has no volume name or host path")]
        }
        if destination.isEmpty {
            return [
                Issue(
                    service: service,
                    message: "“\(mount)” has no mount path — a variable used for the path may be unset")
            ]
        }
        guard VolumeGrouping.volumeName(inMount: mount) == nil else {
            return []  // a named volume; the runtime creates it on demand
        }
        // A host bind: expand ~ and check it's really there.
        let path = NSString(string: source).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: path) else {
            return [Issue(service: service, message: "the host path “\(source)” doesn’t exist")]
        }
        return []
    }

    /// "[host-ip:]host-port:container-port[/protocol]".
    nonisolated private static func portIssues(_ published: String, service: String) -> [Issue] {
        let withoutProtocol = published.split(separator: "/").first.map(String.init) ?? published
        let parts = withoutProtocol.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard (2...3).contains(parts.count) else {
            return [
                Issue(
                    service: service,
                    message: "“\(published)” isn’t a valid port mapping — expected host:container")
            ]
        }
        return parts.suffix(2).compactMap { part in
            guard let port = Int(part), (1...65535).contains(port) else {
                return Issue(service: service, message: "“\(published)” has an invalid port “\(part)”")
            }
            return nil
        }
    }
}
