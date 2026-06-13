//
//  CustomStackSheet.swift
//  ContainerManager
//

import SwiftUI

struct CustomStackSheet: View {
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
    @State private var resultURL: URL?
    @State private var error: PresentedError?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !webImage.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
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
                if isRunning || resultURL != nil || !log.isEmpty {
                    Section {
                        StackRunView(log: log, progress: progress, isRunning: isRunning, resultURL: resultURL)
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isRunning)

            Divider()

            HStack {
                Spacer()
                Button(resultURL == nil ? "Cancel" : "Done") { dismiss() }
                if resultURL == nil {
                    Button("Create") { Task { await run() } }
                        .buttonStyle(.borderedProminent)
                        .disabled(isRunning || !isValid)
                }
            }
            .padding(14)
        }
        .frame(width: 520)
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

        do {
            resultURL = try await StackOrchestrator.run(spec: spec, progress: progress) { line in
                log.append(line)
            }
            await store.refresh()
        } catch {
            self.error = PresentedError(title: "Failed to create stack", error: error)
        }
        isRunning = false
    }

    private func lines(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func tokens(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
    }
}
