//
//  VolumeGrouping.swift
//  ContainerManager
//

import ContainerResource
import Foundation

/// Labels the user has assigned to volumes, stored app-side.
///
/// The runtime accepts labels only when a volume is created (`ClientVolume.create`) and
/// has no update call, so grouping volumes that already exist has to live here. Volumes
/// the app creates for a stack also get a real label on the volume itself — see
/// ``VolumeGrouping/group(for:stacks:)`` for how the two combine.
enum VolumeMetadata {
    private static let key = "volumeLabels"

    static func label(for name: String) -> String? {
        all()[name]
    }

    /// Applies `label` to every named volume, or clears it when nil/empty.
    static func set(_ label: String?, for names: some Sequence<String>) {
        var map = all()
        let trimmed = label?.trimmingCharacters(in: .whitespaces)
        for name in names {
            if let trimmed, !trimmed.isEmpty {
                map[name] = trimmed
            } else {
                map.removeValue(forKey: name)
            }
        }
        UserDefaults.standard.set(map, forKey: key)
    }

    private static func all() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
    }
}

enum VolumeGrouping {
    static let ungrouped = "Ungrouped"

    /// The group a volume belongs to, in order of confidence:
    /// an explicit label the user set, the stack recorded on the volume when it was
    /// created, or a stack that currently mounts it. Nil when it fits none of those.
    ///
    /// The last case is inference from live containers, so it disappears when the stack
    /// is deleted — which is exactly when the volume outlives it. That's why stack
    /// volumes are labelled at creation.
    static func group(for volume: VolumeConfiguration, stacks: [Stack]) -> String? {
        if let label = VolumeMetadata.label(for: volume.name) { return label }
        if let stack = volume.labels[StackLabels.stack] { return stack }
        return stacks.first { stack in
            stack.volumes.contains { $0.name == volume.name }
        }?.name
    }

    /// The volume name in a mount spec, or nil when it's a host bind mount.
    static func volumeName(inMount mount: String) -> String? {
        guard let source = mount.split(separator: ":").first.map(String.init) else { return nil }
        return source.hasPrefix("/") || source.hasPrefix("~") || source.hasPrefix(".") ? nil : source
    }
}
