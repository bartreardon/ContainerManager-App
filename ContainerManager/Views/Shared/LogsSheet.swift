//
//  LogsSheet.swift
//  ContainerManager
//

import Foundation
import SwiftUI

/// Streams log file handles (stdio, and optionally boot) for a machine or container.
struct LogsSheet: View {
    let title: String
    let hasBootLog: Bool
    /// Returns log file handles: index 0 is stdio, index 1 (if present) is the boot log.
    let fetchHandles: () async throws -> [FileHandle]

    @Environment(\.dismiss) private var dismiss
    @State private var streamer = LogStreamer()
    @State private var kind: LogKind = .stdio
    @State private var error: PresentedError?

    enum LogKind: String, CaseIterable {
        case stdio = "Output"
        case boot = "Boot"
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                if hasBootLog {
                    Picker("", selection: $kind) {
                        ForEach(LogKind.allCases, id: \.self) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            LogTextView(text: streamer.text)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 400, idealHeight: 480)
        .errorAlert($error)
        .task(id: kind) {
            await load()
        }
        .onDisappear {
            streamer.stop()
        }
    }

    private func load() async {
        do {
            let handles = try await fetchHandles()
            let index = (kind == .boot && handles.count > 1) ? 1 : 0
            guard handles.indices.contains(index) else {
                error = PresentedError(title: "No logs available", message: "The service returned no log files.")
                return
            }
            for (offset, handle) in handles.enumerated() where offset != index {
                try? handle.close()
            }
            streamer.start(handle: handles[index])
        } catch {
            self.error = PresentedError(title: "Failed to load logs", error: error)
        }
    }
}

struct LogTextView: View {
    let text: String

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(text.isEmpty ? "No output." : text)
                    .font(.caption.monospaced())
                    .foregroundStyle(text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .textSelection(.enabled)
                Color.clear.frame(height: 1).id("logBottom")
            }
            .onChange(of: text) {
                proxy.scrollTo("logBottom")
            }
        }
    }
}
