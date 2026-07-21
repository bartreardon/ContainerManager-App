//
//  StackMetadata.swift
//  ContainerManager
//

import Foundation

/// User-editable presentation metadata for a stack (custom display name + icon).
/// Stacks are reconstructed at runtime from container labels, so this presentation
/// layer is stored app-side, keyed by the stack's internal name, in `UserDefaults`.
struct StackMeta: Codable {
    var displayName: String?
    var icon: String?
}

enum StackMetadata {
    private static let key = "stackMetadata"

    static func get(_ name: String) -> StackMeta {
        all()[name] ?? StackMeta()
    }

    static func set(_ name: String, displayName: String?, icon: String?) {
        var map = all()
        // Store nil/empty display name as absent so it falls back to the stack name.
        let trimmed = displayName?.trimmingCharacters(in: .whitespaces)
        map[name] = StackMeta(displayName: (trimmed?.isEmpty == false) ? trimmed : nil, icon: icon)
        guard let data = try? JSONEncoder().encode(map) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    private static func all() -> [String: StackMeta] {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            let map = try? JSONDecoder().decode([String: StackMeta].self, from: data)
        else { return [:] }
        return map
    }
}

/// A curated set of SF Symbols offered when choosing a stack icon.
enum StackIcons {
    static let `default` = "square.stack.3d.up"

    static let all: [String] = [
        "square.stack.3d.up", "globe", "server.rack", "cylinder.split.1x2", "tablecells",
        "envelope", "arrow.triangle.branch", "chevron.left.forwardslash.chevron.right",
        "doc.richtext", "network", "shippingbox", "cube", "gauge.with.dots.needle.67percent",
        "bolt.horizontal", "externaldrive", "photo", "music.note", "gamecontroller",
        "terminal", "lock.shield", "cloud", "cart", "wand.and.stars", "chart.bar",
    ]
}
