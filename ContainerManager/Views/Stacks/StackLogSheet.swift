//
//  StackLogSheet.swift
//  ContainerManager
//

import SwiftUI

/// Shows a stack's recorded history: what its import couldn't carry over, the creation
/// steps, and any services added or replaced since.
struct StackLogSheet: View {
    let stackName: String

    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(stackName) — Log")
                    .font(.headline)
                Spacer()
                Button("Reveal in Finder") { StackLog.reveal(stackName) }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
            Divider()
            LogTextView(text: text)
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 400, idealHeight: 480)
        .task { text = StackLog.read(for: stackName) }
    }
}
