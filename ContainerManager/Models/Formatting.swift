//
//  Formatting.swift
//  ContainerManager
//

import Foundation

enum Format {
    static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    static func bytes(_ count: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: count, countStyle: .file)
    }
}

extension String {
    /// Drops the default registry/library prefixes from an image reference for display.
    var shortImageReference: String {
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
    var shortDigest: String {
        guard let hex = split(separator: ":").last else { return self }
        return String(hex.prefix(12))
    }

    /// Strips a CIDR suffix ("192.168.64.3/24" → "192.168.64.3").
    var withoutCIDRSuffix: String {
        split(separator: "/").first.map(String.init) ?? self
    }

    /// Lowercases and replaces disallowed characters with hyphens so the result is a
    /// valid network/volume/container resource name (lowercase letters, digits, hyphens).
    var sanitizedResourceName: String {
        let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789-")
        let mapped = String(lowercased().map { allowed.contains($0) ? $0 : "-" })
        let trimmed = mapped.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "stack" : trimmed
    }
}
