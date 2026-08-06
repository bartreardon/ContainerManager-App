//
//  StackRunView.swift
//  ContainerManager
//

import AppKit
import SwiftUI

/// Shared running/result display for the stack create sheets: a step log, the current
/// image fetch/unpack progress, and (on success) the web URL with an Open button.
struct StackRunView: View {
    let log: [String]
    let progress: GuiProgress
    let isRunning: Bool
    var finished: Bool = false
    let resultURL: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !log.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(Array(log.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            Color.clear.frame(height: 1).id("end")
                        }
                        .padding(6)
                    }
                    // Fixed, not max: with maxHeight the box grew as lines arrived, so
                    // the enclosing form scrolled to a target that then moved below the
                    // fold. A stable height keeps the run area where it was scrolled to.
                    .frame(height: 120)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: log.count) { proxy.scrollTo("end") }
                }
            }
            // One status area of a stable height, so the section doesn't grow (and shift
            // the scroll position) as the detail line or the result row appear.
            VStack(alignment: .leading, spacing: 2) {
                if isRunning {
                    if let fraction = progress.fraction {
                        ProgressView(value: fraction) {
                            Text(progress.phase.isEmpty ? "Working — please wait…" : progress.phase)
                                .font(.caption)
                        }
                    } else {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text(progress.phase.isEmpty ? "Working — please wait…" : progress.phase)
                                .font(.caption)
                        }
                    }
                    Text(progress.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let resultURL {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Ready at \(resultURL.absoluteString)").font(.callout)
                        Button("Open") { NSWorkspace.shared.open(resultURL) }
                            .controlSize(.small)
                    }
                } else if finished {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Stack is up.").font(.callout)
                    }
                }
            }
            .frame(height: 34, alignment: .topLeading)
        }
    }
}
