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
    @Environment(StacksStore.self) private var stacksStore

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
    /// Stack to join, or empty for none.
    @State private var stack = ""
    @State private var portsText = ""
    @State private var volumesText = ""
    @State private var autoRemove = false
    @State private var startAfterCreate = true

    @State private var progress = GuiProgress()
    @State private var isCreating = false
    /// Held so Cancel can stop the work rather than only closing the sheet.
    @State private var task: Task<Void, Never>?
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text("Random ID"))
                    ImageReferencePicker(label: "Image", reference: $image, prompt: "e.g. nginx:latest")
                    TextField("Command", text: $command, prompt: Text("Image default"))
                    Picker("Stack", selection: $stack) {
                        Text("None").tag("")
                        ForEach(stacksStore.stacks.map(\.name), id: \.self) { name in
                            Text(name).tag(name)
                        }
                    }
                } header: {
                    Text("Container")
                } footer: {
                    if !stack.isEmpty {
                        Text("Joins the “\(stack)” stack and its network: it's grouped and started with the stack, and deleting the stack deletes it too. It isn't added to the stack's saved definition, so “Re-create” won't restore it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                // Joining a stack means joining its network. Done here, with the
                // consequence spelled out above, because the Network row is further
                // down the sheet and would otherwise appear to change on its own.
                .onChange(of: stack) {
                    guard !stack.isEmpty else { return }
                    let stackNetwork = "\(stack)-net"
                    if networkOptions.contains(stackNetwork) { network = stackNetwork }
                }
                Section {
                    TextEditor(text: $envText)
                        .font(.body.monospaced())
                        .frame(height: 56)
                } header: {
                    HStack {
                        Text("Environment")
                        Spacer()
                        Button {
                            importEnv()
                        } label: {
                            Label("Import from File…", systemImage: "square.and.arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Load a .env file (KEY=value per line)")
                    }
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
                    task?.cancel()
                    dismiss()
                }
                Button("Create") {
                    task = Task { await create() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating || image.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(14)
        }
        .frame(width: 500)
        .onDisappear { task?.cancel() }
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

    /// Loads a `.env` file into the environment field.
    private func importEnv() {
        do {
            guard let text = try EnvFile.pick() else { return }
            envText = EnvFile.parse(text).joined(separator: "\n")
            error = nil
        } catch {
            self.error = PresentedError(title: "Couldn't read file", error: error)
        }
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

        // A stack is expressed as the same labels the orchestrator writes, so the
        // container groups with it and the stack's own actions pick it up.
        var labels: [String] = []
        if !stack.isEmpty {
            labels.append("\(StackLabels.stack)=\(stack)")
            let role = name.trimmingCharacters(in: .whitespaces)
            if !role.isEmpty { labels.append("\(StackLabels.role)=\(role)") }
        }

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
            labels: labels,
            autoRemove: autoRemove,
            startAfterCreate: startAfterCreate
        )
        do {
            try await store.create(spec: spec, progress: progress)
            dismiss()
        } catch is CancellationError {
            // Asked for — the sheet is already closing.
        } catch {
            self.error = PresentedError(title: "Failed to create container", error: error)
        }
        isCreating = false
    }
}
