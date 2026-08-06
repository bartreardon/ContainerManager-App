//
//  StackServiceSheet.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI
// Only the type — importing all of ContainerizationOCI shadows SwiftUI's `State`.
import struct ContainerizationOCI.Platform

/// Adds a service to an existing stack, or replaces one — the way to repair a service
/// that failed to create, or to change an existing one's settings. Saving creates a
/// container carrying the stack's labels and network.
struct StackServiceSheet: View {
    let stackName: String
    /// The service being replaced; nil when adding a new one.
    let replacing: ContainerSnapshot?

    @Environment(\.dismiss) private var dismiss
    @Environment(StacksStore.self) private var store

    @State private var role: String
    @State private var image: String
    @State private var command: String
    @State private var envText: String
    @State private var portsText: String
    @State private var volumesText: String
    @State private var platform: String
    @State private var webURL: String
    @State private var progress = GuiProgress()
    @State private var isRunning = false
    @State private var error: PresentedError?

    init(stackName: String, replacing: ContainerSnapshot? = nil) {
        self.stackName = stackName
        self.replacing = replacing

        let config = replacing?.configuration
        let role = config?.labels[StackLabels.role]
            ?? replacing?.id.replacingOccurrences(of: "\(stackName)-", with: "")
        _role = State(initialValue: role ?? "")
        _image = State(initialValue: config?.image.reference ?? "")
        _command = State(initialValue: Self.commandLine(config?.initProcess))
        _envText = State(initialValue: (config?.initProcess.environment ?? []).joined(separator: "\n"))
        _portsText = State(initialValue: (config?.publishedPorts ?? []).map(Self.portSpec).joined(separator: "\n"))
        _volumesText = State(initialValue: (config?.mounts ?? []).compactMap(Self.mountSpec).joined(separator: "\n"))
        _platform = State(initialValue: config.map { "\($0.platform.os)/\($0.platform.architecture)" } ?? "")
        _webURL = State(initialValue: config?.labels[StackLabels.url] ?? "")
    }

    /// Services from the stack's saved definition, offered as a starting point.
    private var definedServices: [StackServiceSpec] {
        StackDefinitionStore.load(for: stackName)?.plan()?.services ?? []
    }

    private func prefill(from service: StackServiceSpec) {
        role = service.key
        image = service.image
        command = service.command
        platform = service.platform ?? ""
        envText = service.env.joined(separator: "\n")
        portsText = service.publishPorts.joined(separator: "\n")
        volumesText = service.volumes.joined(separator: "\n")
        if let plan = StackDefinitionStore.load(for: stackName)?.plan(),
            service.key == plan.webServiceKey, let port = plan.webPort {
            webURL = "http://localhost:\(port)"
        }
    }

    private var isValid: Bool {
        !role.trimmingCharacters(in: .whitespaces).isEmpty
            && !image.trimmingCharacters(in: .whitespaces).isEmpty
            && !isRunning
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Role", text: $role, prompt: Text("e.g. web"))
                    ImageReferencePicker(label: "Image", reference: $image, prompt: "e.g. nginx:latest")
                    TextField("Command", text: $command, prompt: Text("Image default"))
                    TextField("Platform", text: $platform, prompt: Text("Host default — e.g. linux/amd64"))
                } header: {
                    HStack {
                        Text(replacing == nil ? "New Service" : "Replace “\(role)”")
                        Spacer()
                        // Anything the stack was defined with can be restored as-is,
                        // rather than retyped.
                        if !definedServices.isEmpty {
                            Menu("Prefill from definition") {
                                ForEach(definedServices) { service in
                                    Button(service.key) { prefill(from: service) }
                                }
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .font(.caption)
                        }
                    }
                } footer: {
                    Text("The container will be named “\(stackName)-\(role.isEmpty ? "role" : role)” and joined to the \(stackName)-net network.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Environment") {
                    TextEditor(text: $envText)
                        .font(.body.monospaced())
                        .frame(height: 56)
                }
                Section {
                    TextEditor(text: $portsText)
                        .font(.body.monospaced())
                        .frame(height: 40)
                    TextField("Web URL", text: $webURL, prompt: Text("e.g. http://localhost:8080"))
                } header: {
                    Text("Published Ports")
                } footer: {
                    Text("Setting a web URL gives the stack an “Open in Browser” action, here and in the menu bar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextEditor(text: $volumesText)
                        .font(.body.monospaced())
                        .frame(height: 46)
                } header: {
                    Text("Volumes")
                } footer: {
                    Text("One per line — “name:/path” for a named volume, “/host:/path[:ro]” for a bind.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error {
                    Section {
                        Text(error.message).foregroundStyle(.red).font(.callout)
                    }
                }
                if isRunning {
                    Section {
                        StackRunView(log: [], progress: progress, isRunning: true, finished: false, resultURL: nil)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isRunning)

            Divider()

            HStack {
                if replacing != nil {
                    Text("Replacing deletes the existing container. Named volumes are kept.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                Button(replacing == nil ? "Add" : "Replace") { Task { await save() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValid)
            }
            .padding(14)
        }
        .frame(width: 520)
    }

    private func save() async {
        error = nil
        isRunning = true
        let spec = StackServiceSpec(
            key: role.trimmingCharacters(in: .whitespaces).sanitizedResourceName,
            displayName: role,
            image: image.trimmingCharacters(in: .whitespaces),
            env: lines(envText),
            volumes: lines(volumesText),
            publishPorts: lines(portsText),
            command: command.trimmingCharacters(in: .whitespaces),
            platform: platform.trimmingCharacters(in: .whitespaces).isEmpty
                ? nil : platform.trimmingCharacters(in: .whitespaces)
        )
        do {
            try await store.addService(
                to: stackName, service: spec, replacing: replacing, webURL: webURL, progress: progress)
            dismiss()
        } catch {
            self.error = PresentedError(title: "Failed to save service", error: error)
        }
        isRunning = false
    }

    private func lines(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    /// The runtime stores the executable separately from its arguments, so joining only
    /// `arguments` drops argv[0]: `sh -c "…"` came back as `-c "…"`, and the container
    /// then failed with "failed to find target executable -c".
    private static func commandLine(_ process: ProcessConfiguration?) -> String {
        guard let process else { return "" }
        var argv = process.arguments
        if !process.executable.isEmpty, argv.first != process.executable {
            argv.insert(process.executable, at: 0)
        }
        return ShellWords.join(argv)
    }

    private static func portSpec(_ port: PublishPort) -> String {
        let host = "\(port.hostAddress)"
        let mapping = "\(port.hostPort):\(port.containerPort)"
        return (host.isEmpty || host == "0.0.0.0") ? mapping : "\(host):\(mapping)"
    }

    /// Named volumes and host binds, in the "source:destination[:ro]" form the create
    /// path expects. Other mount kinds (the image's own filesystem) are skipped.
    private static func mountSpec(_ mount: Filesystem) -> String? {
        let source = mount.volumeName ?? mount.source
        guard mount.isVolume || source.hasPrefix("/") else { return nil }
        guard !source.isEmpty, !mount.destination.isEmpty else { return nil }
        return mount.options.readonly ? "\(source):\(mount.destination):ro" : "\(source):\(mount.destination)"
    }
}
