//
//  HelperLogic.swift
//  Shared between ContainerManager and ContainerManagerHelper.
//
//  The decisions the privileged helper makes, kept free of side effects so the app's
//  unit tests can pin them down.
//

import Foundation

/// A local DNS domain and the `/etc/resolver` file that routes it to container's DNS.
nonisolated enum ResolverDomain {
    static let directory = "/etc/resolver"
    /// The prefix container's own `HostDNSResolver` uses, so `container system dns list`
    /// sees domains the helper creates and the helper can delete ones the CLI created.
    static let filePrefix = "containerization."

    /// Dot-separated labels of 1–63 lowercase letters, digits or hyphens, none starting
    /// or ending with a hyphen; 253 characters at most.
    static func isValid(_ domain: String) -> Bool {
        guard !domain.isEmpty, domain.count <= 253 else { return false }
        let labels = domain.split(separator: ".", omittingEmptySubsequences: false)
        return labels.allSatisfy { label in
            guard (1...63).contains(label.count),
                label.first != "-", label.last != "-"
            else { return false }
            return label.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "-" }
        }
    }

    static func fileName(for domain: String) -> String { filePrefix + domain }

    /// Matches what `container system dns create` writes (container 1.4.1), for the
    /// plain case without `--localhost`.
    static func contents(for domain: String) -> String {
        """
        domain \(domain)
        search \(domain)
        nameserver 127.0.0.1
        port 2053

        """
    }
}

/// Whether a package is Apple's container installer, judged from tool output.
nonisolated enum PackageSignature {
    static let installerSigner = "Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)"

    /// `pkgutil --check-signature`: signed for distribution, notarized, and the leaf
    /// certificate is Apple's container installer identity.
    static func pkgutilAccepts(_ output: String) -> Bool {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.contains("Status: signed by a developer certificate issued by Apple for distribution")
            && lines.contains("Notarization: trusted by the Apple notary service")
            && lines.contains("1. \(installerSigner)")
    }

    /// `spctl -a -vv -t install`: Gatekeeper accepts it as notarized, from that signer.
    static func spctlAccepts(_ output: String) -> Bool {
        let lines = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return (lines.first?.hasSuffix(": accepted") ?? false)
            && lines.contains("source=Notarized Developer ID")
            && lines.contains("origin=\(installerSigner)")
    }
}

/// What to remove to uninstall container, from its package receipt.
nonisolated struct UninstallPlan: Equatable {
    static let packageIdentifier = "com.apple.container-installer"
    static let root = "/usr/local"
    /// Shared with everything else installed under /usr/local, so never removed.
    static let keptDirectories: Set<String> = ["bin", "libexec"]

    enum PlanError: Error, Equatable, LocalizedError {
        case unexpectedLocation(String)
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .unexpectedLocation(let location):
                "container's package receipt says it was installed at “\(location)”, not /usr/local."
            case .unsafePath(let path):
                "container's package receipt lists an unsafe path: “\(path)”."
            }
        }
    }

    /// Paths relative to `root`.
    let files: [String]
    /// Relative to `root`, deepest first.
    let directories: [String]

    /// - Parameters:
    ///   - packageInfo: `pkgutil --pkg-info <id>` output.
    ///   - files: `pkgutil --only-files --files <id>` output.
    ///   - directories: `pkgutil --only-dirs --files <id>` output.
    static func make(packageInfo: String, files: String, directories: String) throws -> UninstallPlan {
        let location = packageInfo.split(separator: "\n")
            .first { $0.hasPrefix("location:") }
            .map { $0.dropFirst("location:".count).trimmingCharacters(in: .whitespaces) } ?? ""
        guard location == "usr/local" || location == "/usr/local" else {
            throw PlanError.unexpectedLocation(location)
        }
        let fileList = try relativePaths(files)
        let directoryList = try relativePaths(directories)
            .filter { !keptDirectories.contains($0) }
            .sorted { depth($0) > depth($1) }
        return UninstallPlan(files: fileList, directories: directoryList)
    }

    private static func relativePaths(_ output: String) throws -> [String] {
        try output.split(separator: "\n").map(String.init).filter { !$0.isEmpty }.map { path in
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.hasPrefix("/"),
                components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." })
            else { throw PlanError.unsafePath(path) }
            return path
        }
    }

    private static func depth(_ path: String) -> Int {
        path.split(separator: "/").count
    }
}
