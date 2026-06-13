//
//  WordPressStackSheet.swift
//  ContainerManager
//

import SwiftUI

struct WordPressStackSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StacksStore.self) private var store

    @State private var name = "mysite"
    @State private var dbPassword = "wordpress"
    @State private var webPort = "8080"

    @State private var progress = GuiProgress()
    @State private var log: [String] = []
    @State private var isRunning = false
    @State private var resultURL: URL?
    @State private var error: PresentedError?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !dbPassword.isEmpty
            && Int(webPort) != nil
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Stack name", text: $name, prompt: Text("mysite"))
                    SecureField("Database password", text: $dbPassword)
                    TextField("Web port", text: $webPort, prompt: Text("8080"))
                } header: {
                    Text("WordPress + MariaDB")
                } footer: {
                    Text("Creates a MariaDB database (persistent volume) and a WordPress site on a private network. WordPress is wired to the database automatically. Open the web port in your browser to finish setup.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
        .frame(width: 500)
    }

    private func run() async {
        isRunning = true
        error = nil
        log = []
        let spec = StackTemplates.wordpress(
            name: name.trimmingCharacters(in: .whitespaces),
            dbPassword: dbPassword,
            webPort: Int(webPort) ?? 8080
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
}
