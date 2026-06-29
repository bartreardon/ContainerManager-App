//
//  Pasteboard.swift
//  ContainerManager
//

import AppKit

enum Pasteboard {
    /// Copies items to the general pasteboard as newline-joined plain text.
    static func copy(_ items: [String]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(items.joined(separator: "\n"), forType: .string)
    }
}
