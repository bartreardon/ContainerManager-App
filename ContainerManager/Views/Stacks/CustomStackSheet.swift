//
//  CustomStackSheet.swift
//  ContainerManager
//

import SwiftUI

struct CustomStackSheet: View {
    private static let runSectionID = "run"

    @Environment(\.dismiss) private var dismiss
    @Environment(StacksStore.self) private var store

    @State private var name = "mystack"

    // Web service
    @State private var webImage = ""
    @State private var webPorts = ""
    @State private var webEnv = ""
    @State private var webVolumes = ""

    // Database service (optional)
    @State private var includeDatabase = true
    @State private var dbImage = "postgres:16"
    @State private var dbEnv = "POSTGRES_PASSWORD=secret"
    @State private var dbVolumes = ""
    @State private var dbAddressVar = "DB_HOST"

    @State private var progress = GuiProgress()
    @State private var log: [String] = []
    @State private var isRunning = false
    @State private var outcome: Outcome?

    /// Mirrors TemplateStackSheet: a run that fails partway leaves real containers
    /// behind, so the sheet reports what happened instead of re-arming "Create".
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
    @State private var resultURL: URL?
    @State private var error: PresentedError?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !webImage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
            Form {
                Section("Stack") {
                    TextField("Name", text: $name, prompt: Text("mystack"))
                }
                Section("Web service") {
                    ImageReferencePicker(label: "Image", reference: $webImage, prompt: "e.g. nginx:latest")
                    TextField("Published ports", text: $webPorts, prompt: Text("e.g. 8080:80"))
                    fieldEditor("Environment (KEY=VALUE per line)", text: $webEnv)
                    fieldEditor("Volumes & mounts (one per line)", text: $webVolumes)
                }
                Section {
                    Toggle("Add a database", isOn: $includeDatabase)
                    if includeDatabase {
                        ImageReferencePicker(label: "Image", reference: $dbImage, prompt: "e.g. postgres:16")
                        fieldEditor("Environment (KEY=VALUE per line)", text: $dbEnv)
                        fieldEditor("Volumes & mounts (one per line)", text: $dbVolumes)
                        TextField("Inject DB address into web as", text: $dbAddressVar, prompt: Text("DB_HOST"))
                    }
                } header: {
                    Text("Database")
                } footer: {
                    if includeDatabase {
                        Text("The database starts first; its IP is injected into the web service's environment as the variable above, so the web app can reach it without DNS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
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
                                Text(failure.message).font(.caption).foregroundStyle(.secondary)
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
            .onChange(of: isRunning) {
                guard isRunning else { return }
                withAnimation { proxy.scrollTo(Self.runSectionID, anchor: .bottom) }
            }
            .onChange(of: log.count) { proxy.scrollTo(Self.runSectionID, anchor: .bottom) }
            .onChange(of: outcome != nil) { proxy.scrollTo(Self.runSectionID, anchor: .bottom) }
            }

            Divider()

            HStack {
                Spacer()
                if outcome == nil {
                    Button("Cancel") { dismiss() }
                        .disabled(isRunning)
                    Button("Create") { Task { await run() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || !isValid)
                } else {
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
        .frame(width: 520)
        .frame(minHeight: 360, maxHeight: 620)
    }

    @ViewBuilder
    private func fieldEditor(_ title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            TextEditor(text: text)
                .font(.body.monospaced())
                .frame(height: 46)
        }
    }

    private func run() async {
        isRunning = true
        error = nil
        log = []

        let stackName = name.sanitizedResourceName
        var services: [StackServiceSpec] = []

        if includeDatabase {
            services.append(
                StackServiceSpec(
                    key: "db",
                    displayName: "Database",
                    image: dbImage.trimmingCharacters(in: .whitespaces),
                    env: lines(dbEnv),
                    volumes: lines(dbVolumes),
                    publishPorts: []
                )
            )
        }

        var webEnvLines = lines(webEnv)
        let ipVar = dbAddressVar.trimmingCharacters(in: .whitespaces)
        if includeDatabase, !ipVar.isEmpty {
            webEnvLines.append("\(ipVar)=\(StackToken.ip("db"))")
        }
        let ports = tokens(webPorts)
        services.append(
            StackServiceSpec(
                key: "web",
                displayName: "Web",
                image: webImage.trimmingCharacters(in: .whitespaces),
                env: webEnvLines,
                volumes: lines(webVolumes),
                publishPorts: ports
            )
        )

        let webPort = ports.first.flatMap { Int($0.split(separator: ":").first.map(String.init) ?? "") }
        let spec = StackSpec(
            name: stackName,
            networkName: "\(stackName)-net",
            services: services,
            webServiceKey: "web",
            webPort: webPort
        )

        // Record what this was built from, the same as a template-based stack, so it can
        // be repaired and kept pointing at its dependencies' current addresses.
        let document = StackTemplateDocument.describing(
            spec, id: spec.name, name: spec.name, summary: "Built with the custom stack builder")
        StackDefinitionStore.save(
            StackDefinition(document: document, values: ["name": spec.name, "port": spec.webPort.map(String.init) ?? ""]),
            for: spec.name)

        do {
            resultURL = try await StackOrchestrator.run(spec: spec, progress: progress) { line in
                log.append(line)
            }
            outcome = .succeeded
            await store.refresh()
        } catch {
            await store.refresh()
            let created = store.stack(named: spec.name)?.services.count ?? 0
            if created == 0 {
                StackDefinitionStore.delete(for: spec.name)
                StackLog.delete(for: spec.name)
            }
            log.append("Failed: \(PresentedError.describe(error))")
            outcome = .failed(
                created: created, total: spec.services.count,
                message: PresentedError.describe(error))
        }
        StackLog.append(section: "Create", lines: log, to: spec.name)
        isRunning = false
    }

    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }
}
