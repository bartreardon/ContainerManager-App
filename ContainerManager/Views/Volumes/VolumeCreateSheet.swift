//
//  VolumeCreateSheet.swift
//  ContainerManager
//

import SwiftUI

struct VolumeCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(VolumesStore.self) private var store
    @Environment(StacksStore.self) private var stacksStore

    @State private var name = ""
    /// Stack to group under, or empty for none.
    @State private var stack = ""
    @State private var isCreating = false
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("e.g. pgdata"))
                    Picker("Stack", selection: $stack) {
                        Text("None").tag("")
                        ForEach(stacksStore.stacks.map(\.name), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                } header: {
                    Text("Volume")
                } footer: {
                    Text(
                        stack.isEmpty
                            ? "A local volume stores data on the host and persists across container recreation. Group it under a stack now, or label it later by right-clicking it."
                            : "Grouped with the “\(stack)” stack. Deleting that stack keeps the volume — remove it here if you want the data gone."
                    )
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
            try await store.create(
                name: name.trimmingCharacters(in: .whitespaces), stack: stack)
            dismiss()
        } catch {
            self.error = PresentedError(title: "Failed to create volume", error: error)
        }
        isCreating = false
    }
}
