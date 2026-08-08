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
                StreamedLogView(lines: log, height: 120)
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
