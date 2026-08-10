//
//  Formatting.swift
//  ContainerManager
//

import Foundation

enum Format {
    nonisolated static func bytes(_ count: UInt64) -> String {
        bytes(Int64(count))
    }

    nonisolated static func bytes(_ count: Int64) -> String {
        // Not `ByteCountFormatter.string(fromByteCount:countStyle:)`: that convenience
        // spells zero as the word "Zero", so an idle container's throughput read
        // "Zero KB/s". Fine in prose, wrong in a column of figures.
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }

    /// A byte *rate*, or "—" when the counter wasn't reported.
    ///
    /// Built on `bytes` so throughput and image sizes read alike. That makes it decimal
    /// (MB) where `container stats` prints binary (MiB), so the two disagree by about 7%
    /// — matching the rest of the interface wins, since these numbers sit beside other
    /// app-formatted sizes and never beside the CLI's.
    nonisolated static func rate(_ bytesPerSecond: Double?) -> String {
        guard let bytesPerSecond else { return "—" }
        return "\(bytes(UInt64(max(0, bytesPerSecond.rounded()))))/s"
    }

    /// A percentage to one decimal place, or "—" when unknown.
    nonisolated static func percent(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.number.precision(.fractionLength(1))) + "%"
    }

    /// A process count, or "—" when unknown.
    nonisolated static func count(_ value: UInt64?) -> String {
        guard let value else { return "—" }
        return value.formatted()
    }
}

extension String {
    /// Drops the default registry/library prefixes from an image reference for display.
    nonisolated var shortImageReference: String {
        var ref = self
        for prefix in ["docker.io/library/", "docker.io/"] {
            if ref.hasPrefix(prefix) {
                ref = String(ref.dropFirst(prefix.count))
                break
            }
        }
        return ref
    }

    /// Shortens a "sha256:abcdef…" digest for display.
    nonisolated var shortDigest: String {
        guard let hex = split(separator: ":").last else { return self }
        return String(hex.prefix(12))
    }

    /// Strips a CIDR suffix ("192.168.64.3/24" → "192.168.64.3").
    nonisolated var withoutCIDRSuffix: String {
        split(separator: "/").first.map(String.init) ?? self
    }

    /// Lowercases and replaces disallowed characters with hyphens so the result is a
    /// valid network/volume/container resource name (lowercase letters, digits, hyphens).
    nonisolated var sanitizedResourceName: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let mapped = String(lowercased().map { allowed.contains($0) ? $0 : "-" })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "stack" : trimmed
    }
}
