//
//  ContainerDNS.swift
//  ContainerManager
//

import Foundation

/// Setting up `container`'s local DNS domain, which makes containers reachable from
/// this Mac by name — `my-app.test` rather than `192.168.65.2`.
///
/// Two separate things have to line up, which is why it's easy to end up half
/// configured:
///
/// 1. A **resolver domain**, created with `sudo container system dns create <domain>`.
///    It writes `/etc/resolver/<domain>` so macOS sends those queries to the container
///    service, and needs administrator rights.
/// 2. A **default domain** in `~/.config/container/config.toml`, which is what makes
///    the service give each new container an FQDN to register under. No privileges,
///    but the service only reads the file at startup.
///
/// This is host-to-container only. A container's own resolver is its network gateway,
/// which doesn't answer for container names, so services in a stack still reach each
/// other by address — see `StackOrchestrator`'s `${IP:…}` substitution.
enum ContainerDNS {
    struct State: Equatable {
        /// Domains registered with macOS, from `container system dns list`.
        var resolverDomains: [String] = []
        /// The domain appended to container names, from the service's own config.
        var defaultDomain: String?

        /// Fully working: a default domain that macOS also routes to the service.
        var isActive: Bool {
            guard let defaultDomain else { return false }
            return resolverDomains.contains(defaultDomain)
        }

        /// Set up in part — the usual case being a domain created by following the
        /// tutorial without the config step that actually registers names.
        var isIncomplete: Bool { !isActive && (defaultDomain != nil || !resolverDomains.isEmpty) }
    }

    enum SetupError: LocalizedError {
        case invalidDomain(String)
        case commandFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidDomain(let domain):
                "“\(domain)” isn't a usable domain name. Use letters, digits, hyphens and dots."
            case .commandFailed(let message):
                message
            }
        }
    }

    static var configURL: URL {
        URL.homeDirectory
            .appending(path: ".config/container/config.toml", directoryHint: .notDirectory)
    }

    // MARK: Reading the current state

    static func state() async -> State {
        async let domains = resolverDomains()
        async let fallback = defaultDomain()
        return await State(resolverDomains: domains, defaultDomain: fallback)
    }

    private static func resolverDomains() async -> [String] {
        guard let result = try? await CLIRunner.run(["system", "dns", "list"]) else { return [] }
        return parseDomains(result.output)
    }

    private static func defaultDomain() async -> String? {
        // Read it back from the service rather than the file: the file is only one of
        // the sources it merges, and only what it reports is actually in effect.
        guard let result = try? await CLIRunner.run(["system", "property", "list"]) else {
            return nil
        }
        return parseDefaultDomain(result.output)
    }

    /// Domain names from `container system dns list`, minus its header.
    nonisolated static func parseDomains(_ output: String) -> [String] {
        output
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("DOMAIN") != .orderedSame }
    }

    /// `domain` from the `[dns]` table of a TOML document.
    nonisolated static func parseDefaultDomain(_ toml: String) -> String? {
        var inDNS = false
        for rawLine in toml.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") {
                inDNS = line == "[dns]"
                continue
            }
            guard inDNS, let value = value(ofKey: "domain", in: line), !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private nonisolated static func value(ofKey key: String, in line: String) -> String? {
        let parts = line.split(separator: "=", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count == 2, parts[0] == key else { return nil }
        return parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
    }

    // MARK: Changing it

    /// A domain safe to interpolate into the shell command run with administrator
    /// rights below, and valid as a DNS name.
    nonisolated static func isValidDomain(_ domain: String) -> Bool {
        guard !domain.isEmpty, domain.count <= 253 else { return false }
        guard domain.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == ".") })
        else { return false }
        return !domain.hasPrefix("-") && !domain.hasPrefix(".") && !domain.hasSuffix("-")
            && !domain.hasSuffix(".")
    }

    /// Creates `/etc/resolver/<domain>` via `sudo container system dns create`.
    ///
    /// Run through AppleScript's `with administrator privileges`, so macOS presents its
    /// own authorization dialog and the password never passes through this app. The
    /// domain is validated first because it is interpolated into that command.
    static func createResolverDomain(_ domain: String) async throws {
        guard isValidDomain(domain) else { throw SetupError.invalidDomain(domain) }
        let command = "'\(CLIRunner.containerBinary)' system dns create \(domain)"
        let script = "do shell script \"\(command)\" with administrator privileges"
        let result = try await CLIRunner.run(
            executable: "/usr/bin/osascript", arguments: ["-e", script])
        guard result.exitCode == 0 else {
            // Cancelling the authorization dialog lands here; it isn't a failure worth
            // an alert of its own.
            if result.output.contains("User canceled") { return }
            throw SetupError.commandFailed(result.output)
        }
    }

    /// Writes (or clears) the default domain in the user's config file.
    static func setDefaultDomain(_ domain: String?) throws {
        if let domain, !isValidDomain(domain) { throw SetupError.invalidDomain(domain) }
        let url = configURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        try setting(domain: domain, in: existing).write(to: url, atomically: true, encoding: .utf8)
    }

    /// `toml` with the `[dns]` table's `domain` set to `domain`, or removed when nil.
    ///
    /// Hand-edited rather than parsed and re-emitted: this is the user's file and may
    /// hold settings this app knows nothing about, so everything outside the one key is
    /// passed through untouched.
    nonisolated static func setting(domain: String?, in toml: String) -> String {
        var lines = toml.isEmpty ? [] : toml.components(separatedBy: "\n")
        let entry = domain.map { "domain = \"\($0)\"" }

        guard let sectionStart = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "[dns]" })
        else {
            guard let entry else { return toml }
            // No [dns] table yet: add one, keeping a blank line between tables.
            while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
            if !lines.isEmpty { lines.append("") }
            lines.append(contentsOf: ["[dns]", entry])
            return lines.joined(separator: "\n") + "\n"
        }

        let sectionEnd =
            lines[lines.index(after: sectionStart)...]
            .firstIndex { $0.trimmingCharacters(in: .whitespaces).hasPrefix("[") } ?? lines.endIndex
        let existing = lines[lines.index(after: sectionStart)..<sectionEnd]
            .firstIndex { value(ofKey: "domain", in: $0.trimmingCharacters(in: .whitespaces)) != nil }

        switch (existing, entry) {
        case (let index?, let entry?): lines[index] = entry
        case (let index?, nil): lines.remove(at: index)
        case (nil, let entry?): lines.insert(entry, at: lines.index(after: sectionStart))
        case (nil, nil): break
        }
        return lines.joined(separator: "\n")
    }
}
