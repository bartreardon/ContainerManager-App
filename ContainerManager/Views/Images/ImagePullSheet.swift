//
//  ImagePullSheet.swift
//  ContainerManager
//

import SwiftUI

struct ImagePullSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ImagesStore.self) private var store

    @State private var reference = ""
    @State private var progress = GuiProgress()
    @State private var isPulling = false
    /// Held so Cancel can stop the work rather than only closing the sheet.
    @State private var task: Task<Void, Never>?
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Pull Image") {
                    TextField("Reference", text: $reference, prompt: Text("e.g. nginx:latest"))
                }
                if let error {
                    Section {
                        Text(error.message)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isPulling)

            Divider()

            HStack(spacing: 12) {
                if isPulling {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.phase.isEmpty ? "Pulling…" : progress.phase)
                            .font(.caption)
                        if let fraction = progress.fraction {
                            ProgressView(value: fraction)
                        } else {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text(progress.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: 240, alignment: .leading)
                }
                Spacer()
                Button("Cancel") {
                    task?.cancel()
                    dismiss()
                }
                Button("Pull") {
                    task = Task { await pull() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPulling || reference.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 440)
        .onDisappear { task?.cancel() }
    }

    private func pull() async {
        isPulling = true
        error = nil
        do {
            try await store.pull(
                reference: reference.trimmingCharacters(in: .whitespaces),
                progress: progress
            )
            dismiss()
        } catch is CancellationError {
            // Asked for — the sheet is already closing.
        } catch {
            self.error = PresentedError(title: "Failed to pull image", error: error)
        }
        isPulling = false
    }
}
