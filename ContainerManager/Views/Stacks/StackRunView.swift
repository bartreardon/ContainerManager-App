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
                    .frame(maxHeight: 120)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                    .onChange(of: log.count) { proxy.scrollTo("end") }
                }
            }
            if isRunning {
                if let fraction = progress.fraction {
                    ProgressView(value: fraction) {
                        Text(progress.phase).font(.caption)
                    }
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Text(progress.phase.isEmpty ? "Working…" : progress.phase).font(.caption)
                    }
                }
                if !progress.detail.isEmpty {
                    Text(progress.detail).font(.caption2).foregroundStyle(.secondary)
                }
            }
            if let resultURL {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Ready at \(resultURL.absoluteString)")
                        .font(.callout)
                    Button("Open") { NSWorkspace.shared.open(resultURL) }
                        .controlSize(.small)
                }
            } else if finished {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Stack is up.")
                        .font(.callout)
                }
            }
        }
    }
}
