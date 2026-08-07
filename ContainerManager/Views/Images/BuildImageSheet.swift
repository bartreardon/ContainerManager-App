//
//  BuildImageSheet.swift
//  ContainerManager
//

import AppKit
import SwiftUI

/// Holds the streamed build log. An observable reference type so the `onLine`
/// callback from `CLIRunner` can append lines as they arrive (mirrors the
/// `actionOutput` pattern in `SystemStore`).
@Observable final class BuildSession {
    var log: [String] = []
    var isBuilding = false
}

/// Build a local image from a Dockerfile. The Dockerfile lives in the on-disk
/// ``BuildLibrary`` (under Application Support); its folder is the build context.
/// The result is a normal local image, so it becomes selectable in both the
/// container and machine create sheets via `ImageReferencePicker`.
struct BuildImageSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ImagesStore.self) private var imagesStore

    @State private var name = ""
    @State private var tag = ""
    @State private var dockerfile: String
    @State private var savedBuilds: [String] = []
    @State private var useEnv = false
    @State private var forwardSSH = false
    @State private var envText = ""

    /// `initialDockerfile` seeds the editor (e.g. from an imported/dropped file);
    /// nil starts from a minimal template.
    init(initialDockerfile: String? = nil) {
        _dockerfile = State(initialValue: initialDockerfile ?? "FROM alpine:latest\n")
    }

    @State private var session = BuildSession()
    @State private var built = false
    @State private var builtTag: String?
    @State private var error: PresentedError?

    @State private var showMachineCreate = false
    @State private var showContainerCreate = false

    private var sanitizedName: String { name.sanitizedResourceName }
    private var derivedTag: String { "local/\(sanitizedName):latest" }
    private var effectiveTag: String {
        let t = tag.trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? derivedTag : t
    }
    private var canBuild: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !dockerfile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !session.isBuilding
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    HStack(spacing: 6) {
                        TextField("Name", text: $name, prompt: Text("e.g. my-app"))
                        if !savedBuilds.isEmpty {
                            Menu {
                                Section("Saved Builds") {
                                    ForEach(savedBuilds, id: \.self) { saved in
                                        Button(saved) { load(saved) }
                                    }
                                }
                            } label: {
                                Image(systemName: "chevron.up.chevron.down")
                            }
                            .menuStyle(.borderlessButton)
                            .menuIndicator(.hidden)
                            .fixedSize()
                            .help("Load a saved build")
                        }
                    }
                    TextField("Image tag", text: $tag, prompt: Text(derivedTag))
                } header: {
                    Text("Build")
                } footer: {
                    Text(
                        "Saved under Application Support › ContainerManager › Builds › \(sanitizedName). The folder is the build context, so COPY/ADD resolve against files you add there."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Section {
                    TextEditor(text: $dockerfile)
                        .font(.body.monospaced())
                        .frame(minHeight: 150)
                } header: {
                    HStack {
                        Text("Dockerfile")
                        Spacer()
                        Button {
                            importDockerfile()
                        } label: {
                            Label("Import from File…", systemImage: "square.and.arrow.down")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Load a Dockerfile from disk into the editor")
                    }
                }

                Section {
                    Toggle("Forward SSH agent to the build", isOn: $forwardSSH)
                } footer: {
                    Text("Lets the Dockerfile reach private repositories with your SSH agent — use `RUN --mount=type=ssh …`. Nothing is written into the image.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Toggle("Set environment variables", isOn: $useEnv)
                    if useEnv {
                        TextEditor(text: $envText)
                            .font(.body.monospaced())
                            .frame(minHeight: 70)
                    }
                } header: {
                    HStack {
                        Text("Environment")
                        Spacer()
                        if useEnv {
                            Button {
                                importEnv()
                            } label: {
                                Label("Import from File…", systemImage: "square.and.arrow.down")
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help("Load a .env file (KEY=value per line)")
                        }
                    }
                } footer: {
                    if useEnv {
                        Text(
                            "One KEY=value per line. Passed as build arguments (for matching ARG lines) and baked into the image as ENV defaults, so containers run from it inherit them."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                if !session.log.isEmpty {
                    Section("Output") {
                        logView
                    }
                }

                if let error {
                    Section {
                        Text(error.message)
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if built, let builtTag {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Built \(builtTag.shortImageReference)")
                                .font(.callout)
                        }
                        HStack(spacing: 8) {
                            Button("Create Machine from Image") { showMachineCreate = true }
                            Button("Run Container from Image") { showContainerCreate = true }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack(spacing: 12) {
                Button("Reveal in Finder") { BuildLibrary.reveal(sanitizedName) }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if session.isBuilding {
                    ProgressView().controlSize(.small)
                }
                Button(built ? "Done" : "Cancel") { dismiss() }
                Button("Build") { Task { await build() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(!canBuild)
            }
            .padding(14)
        }
        .frame(width: 560, height: 640)
        .task { refreshSaved() }
        .sheet(isPresented: $showMachineCreate) {
            MachineCreateSheet(initialImage: builtTag)
        }
        .sheet(isPresented: $showContainerCreate) {
            ContainerCreateSheet(initialImage: builtTag ?? "")
        }
    }

    private var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(session.log.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(6)
            }
            .frame(height: 160)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
            .onChange(of: session.log.count) { proxy.scrollTo("end") }
        }
    }

    private func refreshSaved() {
        savedBuilds = BuildLibrary.list()
    }

    /// Loads a Dockerfile from disk into the editor. Dockerfiles often have no
    /// extension, so any file is selectable.
    private func importDockerfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a Dockerfile to load into the editor"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            dockerfile = try String(contentsOf: url, encoding: .utf8)
            error = nil
        } catch {
            self.error = PresentedError(title: "Couldn't read file", error: error)
        }
    }

    /// Loads a `.env` file into the environment field.
    private func importEnv() {
        do {
            guard let text = try EnvFile.pick() else { return }
            envText = text
            error = nil
        } catch {
            self.error = PresentedError(title: "Couldn't read file", error: error)
        }
    }

    private func load(_ saved: String) {
        name = saved
        tag = ""
        dockerfile = BuildLibrary.loadDockerfile(saved)
        envText = BuildLibrary.loadEnv(saved)
        useEnv = !envText.isEmpty
        built = false
        builtTag = nil
        error = nil
        session.log = []
    }

    /// A compose file pasted into the Dockerfile editor is a common mix-up, and
    /// `container build` only reports it as "unknown instruction: services:".
    private var looksLikeCompose: Bool {
        let lines = dockerfile.split(whereSeparator: \.isNewline).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        let hasComposeKeys = lines.contains { $0 == "services:" || $0.hasPrefix("services:") }
        let hasInstructions = lines.contains {
            let upper = $0.uppercased()
            return upper.hasPrefix("FROM ") || upper.hasPrefix("ARG ")
        }
        return hasComposeKeys && !hasInstructions
    }

    private func build() async {
        guard !looksLikeCompose else {
            error = PresentedError(
                title: "That looks like a docker-compose file",
                message:
                    "This editor takes a Dockerfile (FROM, RUN, COPY…). To turn a compose file into a running stack, use Stacks ▸ New Stack ▸ Import Template… instead."
            )
            return
        }
        let buildName = sanitizedName
        error = nil
        built = false
        session.log = []
        session.isBuilding = true
        let useTag = effectiveTag
        let env = useEnv ? EnvFile.parse(envText) : []
        do {
            try BuildLibrary.saveDockerfile(buildName, contents: dockerfile)
            try BuildLibrary.saveEnv(buildName, contents: useEnv ? envText : "")
            name = buildName  // reflect the sanitized folder name back to the field
            try await ImageBuilder.build(
                name: buildName, tag: useTag, env: env, forwardSSH: forwardSSH
            ) { line in
                session.log.append(line)
            }
            builtTag = useTag
            built = true
            await imagesStore.refresh()
            refreshSaved()
        } catch {
            self.error = PresentedError(title: "Build failed", error: error)
        }
        session.isBuilding = false
    }
}
