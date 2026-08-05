//
//  TemplateStackSheet.swift
//  ContainerManager
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// A create sheet driven by a `StackTemplateDef`: renders the template's fields,
/// builds a `StackSpec`, and runs the orchestrator with a shared progress/log view.
struct TemplateStackSheet: View {
    private static let runSectionID = "run"

    let template: StackTemplateDef

    @Environment(\.dismiss) private var dismiss
    @Environment(StacksStore.self) private var store

    @State private var values: [String: String]
    @State private var progress = GuiProgress()
    @State private var log: [String] = []
    @State private var isRunning = false
    @State private var finished = false
    @State private var resultURL: URL?
    @State private var error: PresentedError?

    init(template: StackTemplateDef) {
        self.template = template
        _values = State(initialValue: Dictionary(
            uniqueKeysWithValues: template.fields.map { ($0.key, $0.defaultValue) }
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                Form {
                    Section {
                        ForEach(template.fields) { field in
                            fieldView(field)
                        }
                    } header: {
                        Text(template.name)
                    } footer: {
                        Text(template.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let error {
                        Section {
                            Text(error.message).foregroundStyle(.red).font(.callout)
                        }
                    }
                    if isRunning || finished || !log.isEmpty {
                        Section {
                            StackRunView(log: log, progress: progress, isRunning: isRunning, finished: finished, resultURL: resultURL)
                        }
                        .id(Self.runSectionID)
                    }
                }
                .formStyle(.grouped)
                .disabled(isRunning)
                // Creating a stack pulls images and can take minutes; make sure the
                // progress view is on screen rather than below the fold.
                .onChange(of: isRunning) {
                    guard isRunning else { return }
                    withAnimation { proxy.scrollTo(Self.runSectionID, anchor: .bottom) }
                }
            }

            Divider()

            HStack {
                if template.document != nil {
                    Button("Export…") { exportDefinition() }
                        .help("Save this stack definition as a .containerstack file to share or customise")
                }
                Button("Import .env…") { importEnvValues() }
                    .help("Fill the fields above from an env file (KEY=value per line)")
                Spacer()
                Button(finished ? "Done" : "Cancel") { dismiss() }
                if !finished {
                    Button("Create") { Task { await run() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                }
            }
            .padding(14)
        }
        .frame(width: 500)
    }

    @ViewBuilder
    private func fieldView(_ field: StackTemplateField) -> some View {
        let binding = Binding(
            get: { values[field.key] ?? "" },
            set: { values[field.key] = $0 }
        )
        switch field.kind {
        case .text, .port:
            TextField(field.label, text: binding, prompt: Text(field.placeholder))
        case .password:
            SecureField(field.label, text: binding, prompt: Text(field.placeholder))
        case .directory:
            LabeledContent(field.label) {
                HStack(spacing: 8) {
                    Text(binding.wrappedValue.isEmpty ? "None selected" : binding.wrappedValue)
                        .foregroundStyle(binding.wrappedValue.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Button("Choose…") { chooseFolder(into: field.key) }
                }
            }
        }
    }

    /// Saves the template's declarative definition for sharing or hand-editing.
    private func exportDefinition() {
        guard let document = template.document else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.containerstack]
        panel.nameFieldStringValue = "\(document.id).containerstack"
        panel.message = "Export this stack definition"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try document.encoded().write(to: url, options: .atomic)
        } catch {
            self.error = PresentedError(title: "Export failed", error: error)
        }
    }

    /// Fills the fields above from an env file, so the values can live anywhere rather
    /// than only in a `.env` beside the compose file. Field keys are matched
    /// case-insensitively, since compose variables are conventionally uppercase.
    private func importEnvValues() {
        do {
            guard let text = try EnvFile.pick() else { return }
            var byKey: [String: String] = [:]
            for entry in EnvFile.parse(text) {
                guard let separator = entry.firstIndex(of: "=") else { continue }
                byKey[String(entry[..<separator]).lowercased()] = String(entry[entry.index(after: separator)...])
            }

            let matched = template.fields.filter { byKey[$0.key.lowercased()] != nil }
            for field in matched {
                values[field.key] = byKey[field.key.lowercased()]
            }
            error =
                matched.isEmpty
                ? PresentedError(
                    title: "Nothing matched",
                    message: "No entries in that file match this stack's fields: \(template.fields.map(\.key).joined(separator: ", ")).")
                : nil
        } catch {
            self.error = PresentedError(title: "Couldn't read file", error: error)
        }
    }

    private func chooseFolder(into key: String) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            values[key] = url.path
        }
    }

    private func run() async {
        error = nil
        let spec: StackSpec
        do {
            spec = try template.build(values)
        } catch {
            self.error = PresentedError(title: "Invalid configuration", error: error)
            return
        }

        isRunning = true
        // Seed a line so the progress section appears immediately — the first pull can
        // run for a while before the orchestrator reports its first step.
        log = ["Preparing “\(spec.name)”… (images may need downloading)"]
        do {
            resultURL = try await StackOrchestrator.run(spec: spec, progress: progress) { line in
                log.append(line)
            }
            // Keep what the stack was built from, so a service that failed (or is
            // added later) can be re-created without re-entering everything.
            if let document = template.document {
                StackDefinitionStore.save(
                    StackDefinition(document: document, values: values), for: spec.name)
            }
            finished = true
            await store.refresh()
        } catch {
            self.error = PresentedError(title: "Failed to create stack", error: error)
        }
        isRunning = false
    }
}
