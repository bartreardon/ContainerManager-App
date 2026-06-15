//
//  MachineCreateSheet.swift
//  ContainerManager
//

import ContainerPersistence
import SwiftUI

struct MachineCreateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MachinesStore.self) private var store

    @State private var name = ""
    @State private var image = "alpine:3.22"
    @State private var cpus = MachineConfig.defaultCPUs

    /// `initialImage` pre-fills the image field — e.g. when opened from the build sheet
    /// with a freshly built tag. `nil` keeps the default.
    init(initialImage: String? = nil) {
        if let initialImage { _image = State(initialValue: initialImage) }
    }
    @State private var memory = MachineConfig.defaultMemory.formatted
    @State private var homeMount: MachineConfig.HomeMountOption = MachineConfig.defaultHomeMount
    @State private var setAsDefault = false
    @State private var bootAfterCreate = true

    @State private var progress = GuiProgress()
    @State private var isCreating = false
    @State private var error: PresentedError?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField(
                        "Name",
                        text: $name,
                        prompt: Text(MachinesStore.derivedName(fromImage: image))
                    )
                    ImageReferencePicker(label: "Image", reference: $image, prompt: "alpine:3.22")
                } header: {
                    Text("Machine")
                } footer: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Machine images must include an init system at /sbin/init. alpine works out of the box; plain ubuntu/debian images do not.")
                        Link(
                            "Learn about machine images",
                            destination: URL(string: "https://github.com/apple/container/blob/main/docs/container-machine.md")!
                        )
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section("Resources") {
                    Stepper(value: $cpus, in: 1...64) {
                        LabeledContent("CPUs", value: "\(cpus)")
                    }
                    TextField("Memory", text: $memory, prompt: Text("e.g. 4gb"))
                    Picker("Home Directory", selection: $homeMount) {
                        Text("Read & Write").tag(MachineConfig.HomeMountOption.rw)
                        Text("Read Only").tag(MachineConfig.HomeMountOption.ro)
                        Text("Not Mounted").tag(MachineConfig.HomeMountOption.none)
                    }
                }
                Section {
                    Toggle("Set as default machine", isOn: $setAsDefault)
                    Toggle("Boot after creation", isOn: $bootAfterCreate)
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
                .disabled(isCreating || image.isEmpty)
            }
            .padding(14)
        }
        .frame(width: 480)
    }

    private func create() async {
        isCreating = true
        error = nil
        let spec = MachineCreateSpec(
            name: name.trimmingCharacters(in: .whitespaces),
            image: image.trimmingCharacters(in: .whitespaces),
            cpus: cpus,
            memory: memory,
            homeMount: homeMount,
            setAsDefault: setAsDefault,
            bootAfterCreate: bootAfterCreate
        )
        do {
            try await store.create(spec: spec, progress: progress)
            dismiss()
        } catch {
            self.error = PresentedError(title: "Failed to create machine", error: error)
        }
        isCreating = false
    }
}
