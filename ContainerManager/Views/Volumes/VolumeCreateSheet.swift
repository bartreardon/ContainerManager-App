//
//  VolumeCreateSheet.swift
//  ContainerManager
//

import SwiftUI

struct VolumeCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VolumesStore.self) private var store

    @State private var name = ""
    @State private var isCreating = false
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. pgdata"))
                } header: {
                    Text("Volume")
                } footer: {
                    Text("A local volume stores data on the host and persists across container recreation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            .disabled(isCreating)

            Divider()

            HStack(spacing: 12) {
                if isCreating {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Create") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 420)
    }

    private func create() async {
        isCreating = true
        error = nil
        do {
            try await store.create(name: name.trimmingCharacters(in: .whitespaces))
            dismiss()
        } catch {
            self.error = PresentedError(title: "Failed to create volume", error: error)
        }
        isCreating = false
    }
}
