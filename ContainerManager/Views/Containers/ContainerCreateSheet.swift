//
//  ContainerCreateSheet.swift
//  ContainerManager
//

import SwiftUI

struct ContainerCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ContainersStore.self) private var store
    @Environment(NetworksStore.self) private var networksStore
    @Environment(VolumesStore.self) private var volumesStore

    @State private var name = ""
    @State private var image = ""
    @State private var command = ""

    /// `initialImage` pre-fills the image field — e.g. when opened from the build sheet
    /// with a freshly built tag.
    init(initialImage: String = "") {
        _image = State(initialValue: initialImage)
    }
    @State private var envText = ""
    @State private var cpusText = ""
    @State private var memory = ""
    @State private var network = "default"
    @State private var portsText = ""
    @State private var volumesText = ""
    @State private var autoRemove = false
    @State private var startAfterCreate = true

    @State private var progress = GuiProgress()
    @State private var isCreating = false
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Container") {
                    TextField("Name", text: $name, prompt: Text("Random ID"))
                    ImageReferencePicker(label: "Image", reference: $image, prompt: "e.g. nginx:latest")
                    TextField("Command", text: $command, prompt: Text("Image default"))
                }
                Section {
                    TextEditor(text: $envText)
                        .font(.body.monospaced())
                        .frame(height: 56)
                } header: {
                    Text("Environment")
                } footer: {
                    Text("One KEY=VALUE per line.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Resources") {
                    TextField("CPUs", text: $cpusText, prompt: Text("Default"))
                    TextField("Memory", text: $memory, prompt: Text("Default — e.g. 1G"))
                }
                Section("Networking") {
                    Picker("Network", selection: $network) {
                        ForEach(networkOptions, id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                    TextField("Published ports", text: $portsText, prompt: Text("e.g. 8080:80 8443:443/tcp"))
                }
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Volumes & mounts")
                                .font(.callout)
                            Spacer()
                            if !volumesStore.selectableNames.isEmpty {
                                Menu {
                                    ForEach(volumesStore.selectableNames, id: \.self) { name in
                                        Button(name) { insertVolume(name) }
                                    }
                                } label: {
                                    Label("Add Volume", systemImage: "plus.circle")
                                        .labelStyle(.iconOnly)
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                                .help("Insert an existing volume")
                            }
                        }
                        TextEditor(text: $volumesText)
                            .font(.body.monospaced())
                            .frame(height: 52)
                    }
                } footer: {
                    Text("One per line. `name:/path` mounts a named volume (created if needed, persists). `/host/path:/path[:ro]` bind-mounts a host folder.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Remove after exit", isOn: $autoRemove)
                    Toggle("Start after create", isOn: $startAfterCreate)
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
                    VStack(alignment: .leading, spacing: 3) {
                        Text(progress.phase.isEmpty ? "Preparing…" : progress.phase)
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
                Button("Create") {
                    Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || image.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 500)
        .task {
            if networksStore.networks.isEmpty {
                await networksStore.refresh()
            }
            if volumesStore.volumes.isEmpty {
                await volumesStore.refresh()
            }
        }
    }

    /// Network names with the built-in "default" guaranteed present and first.
    private var networkOptions: [String] {
        let names = networksStore.selectableNames
        return names.contains("default") ? names : ["default"] + names
    }

    private func insertVolume(_ name: String) {
        let prefix = volumesText.isEmpty || volumesText.hasSuffix("\n") ? "" : "\n"
        volumesText += "\(prefix)\(name):/"
    }

    private func create() async {
        isCreating = true
        error = nil

        let env = envText
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let ports = portsText
            .split(whereSeparator: { $0 == "," || $0.isWhitespace })
            .map(String.init)
        let volumes = volumesText
            .split(whereSeparator: { $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let spec = ContainerCreateSpec(
            name: name.trimmingCharacters(in: .whitespaces),
            image: image.trimmingCharacters(in: .whitespaces),
            command: command,
            env: env,
            cpus: Int64(cpusText.trimmingCharacters(in: .whitespaces)),
            memory: memory.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil
                : memory.trimmingCharacters(in: .whitespaces),
            network: network,
            publishPorts: ports,
            volumes: volumes,
            autoRemove: autoRemove,
            startAfterCreate: startAfterCreate
        )
        do {
            try await store.create(spec: spec, progress: progress)
            dismiss()
        } catch {
            self.error = PresentedError(title: "Failed to create container", error: error)
        }
        isCreating = false
    }
}
