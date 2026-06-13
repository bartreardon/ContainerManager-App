//
//  NetworkCreateSheet.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct NetworkCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(NetworksStore.self) private var store

    @State private var name = ""
    @State private var mode: NetworkMode = .nat
    @State private var subnet = ""
    @State private var isCreating = false
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Network") {
                    TextField("Name", text: $name, prompt: Text("e.g. devnet"))
                    Picker("Mode", selection: $mode) {
                        Text("NAT").tag(NetworkMode.nat)
                        Text("Host-only").tag(NetworkMode.hostOnly)
                    }
                }
                Section {
                    TextField("IPv4 subnet", text: $subnet, prompt: Text("e.g. 192.168.65.0/24"))
                } footer: {
                    Text("Optional — leave empty to let the network plugin assign a subnet automatically.")
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
        .frame(width: 440)
    }

    private func create() async {
        isCreating = true
        error = nil
        do {
            try await store.create(
                name: name.trimmingCharacters(in: .whitespaces),
                mode: mode,
                subnet: subnet.trimmingCharacters(in: .whitespaces)
            )
            dismiss()
        } catch {
            self.error = PresentedError(title: "Failed to create network", error: error)
        }
        isCreating = false
    }
}
