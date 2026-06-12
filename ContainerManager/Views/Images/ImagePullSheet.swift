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
                    dismiss()
                }
                Button("Pull") {
                    Task { await pull() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPulling || reference.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 440)
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
        } catch {
            self.error = PresentedError(title: "Failed to pull image", error: error)
        }
        isPulling = false
    }
}
