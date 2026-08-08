//
//  StreamedLogView.swift
//  ContainerManager
//

import SwiftUI

/// An inline box showing a log as it arrives — a build, a `system start`, a stack run.
///
/// Wraps ``LogTextView``, which renders the whole log as one selectable `Text`. The
/// three places this replaced each built a `Text` per line inside a plain `VStack`, so
/// every appended line re-diffed the entire stack; BuildKit output runs to thousands of
/// lines. It also means the log can be selected and copied in one drag, which only the
/// build sheet allowed before.
struct StreamedLogView: View {
    let lines: [String]
    /// Fixed rather than a maximum: a box that grows as lines arrive moves the scroll
    /// target out from under the enclosing form mid-run.
    var height: CGFloat = 160

    var body: some View {
        LogTextView(text: lines.joined(separator: "\n"))
            .frame(height: height)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
    }
}
