//
//  GroupedList.swift
//  ContainerManager
//

import SwiftUI

/// Shared pieces for the collapsible groups used by the Volumes, Containers, Networks
/// and Images lists, so they behave identically and there's one place to fix.
enum ListGroups {
    /// Groups every list falls back to.
    static let ungrouped = "Ungrouped"
    static let unused = "Unused"
    /// More than one thing uses the item, so it belongs to no single group.
    static let shared = "Shared"

    /// Orders groups alphabetically, keeping the catch-all buckets at the end where
    /// they read as leftovers rather than as peers.
    static func sorted<T>(_ groups: [(name: String, items: [T])]) -> [(name: String, items: [T])] {
        let last = [shared, ungrouped, unused]
        return groups.sorted { first, second in
            let a = last.firstIndex(of: first.name) ?? -1
            let b = last.firstIndex(of: second.name) ?? -1
            if a != b { return a < b }
            return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
        }
    }

    /// A binding for one group's expansion, backed by a newline-separated list of the
    /// collapsed ones — `@SceneStorage` only holds plain values.
    static func expansion(of name: String, collapsed: Binding<String>) -> Binding<Bool> {
        Binding(
            get: { !collapsed.wrappedValue.split(separator: "\n").contains(Substring(name)) },
            set: { expanded in
                var names = Set(collapsed.wrappedValue.split(separator: "\n").map(String.init))
                if expanded { names.remove(name) } else { names.insert(name) }
                collapsed.wrappedValue = names.sorted().joined(separator: "\n")
            })
    }
}

/// A collapsible section header: a disclosure chevron, the group's name and count, with
/// the whole row as the hit area.
///
/// Built by hand rather than with `Section(isExpanded:)`, which only draws a disclosure
/// control in a `.sidebar`-styled list — elsewhere it's silently ignored, leaving a
/// collapse state with no way to change it.
struct GroupHeader: View {
    let name: String
    let count: Int
    @Binding var isExpanded: Bool

    var body: some View {
        Button {
            withAnimation { isExpanded.toggle() }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text("\(name) (\(count))")
                Spacer()
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(name), \(count) items")
        .accessibilityHint(isExpanded ? "Collapse" : "Expand")
    }
}
