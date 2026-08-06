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
    @State private var outcome: Outcome?
    @State private var resultURL: URL?
    @State private var error: PresentedError?

    /// How a create run ended. A run that fails partway leaves real containers behind,
    /// so the sheet has to say what happened rather than just re-arming "Create".
    private enum Outcome {
        case succeeded
        case failed(created: Int, total: Int, message: String)
    }

    private var succeeded: Bool {
        if case .succeeded = outcome { return true }
        return false
    }

    private var failure: (created: Int, total: Int, message: String)? {
        guard case .failed(let created, let total, let message) = outcome else { return nil }
        return (created, total, message)
    }

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
                    if let failure {
                        Section {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Created \(failure.created) of \(failure.total) services")
                                        .fontWeight(.medium)
                                    Text(failure.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if isRunning || outcome != nil || !log.isEmpty {
                        Section {
                            StackRunView(log: log, progress: progress, isRunning: isRunning, finished: succeeded, resultURL: resultURL)
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
                // Re-pin as the run section fills in: scrolling once at the start left
                // the progress below the fold as soon as content arrived.
                .onChange(of: log.count) {
                    proxy.scrollTo(Self.runSectionID, anchor: .bottom)
                }
                .onChange(of: outcome != nil) {
                    proxy.scrollTo(Self.runSectionID, anchor: .bottom)
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
                if outcome == nil {
                    Button("Cancel") { dismiss() }
                        .disabled(isRunning)
                    Button("Create") { Task { await run() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                } else {
                    // The run is over either way — "Cancel" would be a lie, and a
                    // re-armed "Create" reads as though it still needs pressing.
                    if failure != nil {
                        Button("Retry") { Task { await run() } }
                            .disabled(isRunning)
                    }
                    Button("Close") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning)
                }
            }
            .padding(14)
        }
        // Bounded so the form scrolls once the run log appears, instead of growing the
        // sheet past the screen and stranding the buttons.
        .frame(width: 500)
        .frame(minHeight: 360, maxHeight: 620)
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
        outcome = nil
        let spec: StackSpec
        do {
            spec = try template.build(values)
        } catch {
            // Nothing ran, so this stays a plain field error — Create is still the
            // right next step once the values are fixed.
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
            outcome = .succeeded
            await store.refresh()
        } catch {
            // A failure partway leaves the services created so far running, so report
            // how far it got rather than implying nothing happened.
            await store.refresh()
            let created = store.stack(named: spec.name)?.services.count ?? 0
            log.append("Failed: \(PresentedError.describe(error))")
            outcome = .failed(
                created: created,
                total: spec.services.count,
                message: PresentedError.describe(error))
        }
        isRunning = false
    }
}
