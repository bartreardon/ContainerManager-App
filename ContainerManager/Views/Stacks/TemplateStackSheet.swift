//
//  TemplateStackSheet.swift
//  ContainerManager
//

import AppKit
import SwiftUI

/// A create sheet driven by a `StackTemplateDef`: renders the template's fields,
/// builds a `StackSpec`, and runs the orchestrator with a shared progress/log view.
struct TemplateStackSheet: View {
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
                }
            }
            .formStyle(.grouped)
            .disabled(isRunning)

            Divider()

            HStack {
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
        log = []
        do {
            resultURL = try await StackOrchestrator.run(spec: spec, progress: progress) { line in
                log.append(line)
            }
            finished = true
            await store.refresh()
        } catch {
            self.error = PresentedError(title: "Failed to create stack", error: error)
        }
        isRunning = false
    }
}
