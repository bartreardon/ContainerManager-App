//
//  StackDNS.swift
//  ContainerManager
//

import Foundation

/// The names stack services reach each other by, as in Compose: `db` from inside any
/// service of the stack, rather than an address baked in when it was created.
///
/// Built on container 1.6's network attachment aliases, which come with two rules that
/// shape this:
///
/// - An alias needs at least two labels, and only resolves under the default DNS domain:
///   a container's resolver is the network gateway, which hands queries to macOS, and
///   macOS only sends the default domain's names to the container service (see
///   `ContainerDNS`). Without a default domain there's nothing to put names under, so
///   no aliases are set and stacks rely on `${IP:…}` alone.
/// - Exact aliases are unique across every container, so `db.test` could only belong to
///   one stack. Each stack gets its own subdomain, `<stack>.<domain>`, which the
///   services also search — that's what makes a bare `db` resolve.
enum StackDNS {
    struct Settings: Equatable {
        /// Fully qualified, for `ContainerCreateSpec.networkAliases`.
        var aliases: [String]
        /// For `ContainerCreateSpec.dnsSearchDomains`.
        var searchDomains: [String]

        static let none = Settings(aliases: [], searchDomains: [])
    }

    /// The domain a stack's names live under, or nil when there's no default domain or
    /// the stack's name can't be part of a DNS name.
    nonisolated static func domain(forStack stack: String, defaultDomain: String?) -> String? {
        guard let defaultDomain = defaultDomain.map(normalized), !defaultDomain.isEmpty else { return nil }
        let domain = "\(normalized(stack)).\(defaultDomain)"
        return isValidName(domain) ? domain : nil
    }

    /// Aliases and search domains for a service: its key and `extraNames`, each under
    /// the stack's domain. A name another service already answers to (`taken`, as bare
    /// names), or one that isn't a valid DNS name, is left out — the runtime would reject
    /// the whole container for it.
    nonisolated static func settings(
        stack: String, key: String, extraNames: [String] = [], taken: Set<String> = [],
        defaultDomain: String?
    ) -> Settings {
        guard let stackDomain = domain(forStack: stack, defaultDomain: defaultDomain) else { return .none }
        var seen = Set(taken.map(normalized))
        var aliases: [String] = []
        for name in ([key] + extraNames).map(normalized) where !name.isEmpty {
            let alias = "\(name).\(stackDomain)"
            guard isValidName(alias), seen.insert(name).inserted else { continue }
            aliases.append(alias)
        }
        guard !aliases.isEmpty else { return .none }
        // The runtime's limit per attachment.
        aliases = Array(aliases.prefix(32))
        // Searching only the stack's domain would replace the resolver's default of the
        // default domain, so `other-container` stops resolving; keep it second.
        let searchDomains = [stackDomain] + [defaultDomain.map(normalized)].compactMap { $0 }
        return Settings(aliases: aliases, searchDomains: searchDomains)
    }

    /// The bare names a container's aliases were made from, recovered with the stack
    /// domain it searches first. Aliases outside that domain are skipped.
    nonisolated static func names(fromAliases aliases: [String], searchDomains: [String]) -> [String] {
        guard let stackDomain = searchDomains.first.map(normalized), !stackDomain.isEmpty else { return [] }
        let suffix = ".\(stackDomain)"
        return aliases.map(normalized).compactMap { alias in
            guard alias.hasSuffix(suffix), alias.count > suffix.count else { return nil }
            return String(alias.dropLast(suffix.count))
        }
    }

    private nonisolated static func normalized(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespaces).lowercased()
        return trimmed.hasSuffix(".") ? String(trimmed.dropLast()) : trimmed
    }

    /// What container's `DNSName` accepts: labels of letters, digits, hyphens and
    /// underscores that start and end with a letter or digit.
    nonisolated static func isValidName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 253 else { return false }
        return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            label.count <= 63 && label.wholeMatch(of: /[a-zA-Z0-9](?:[a-zA-Z0-9\-_]*[a-zA-Z0-9])?/) != nil
        }
    }
}
