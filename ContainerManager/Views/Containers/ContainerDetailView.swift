//
//  ContainerDetailView.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import SwiftUI
import struct ContainerizationOCI.Platform

private enum ContainerDetailMode: String, CaseIterable {
    case info = "Details"
    case terminal = "Terminal"
}

struct ContainerDetailView: View {
    let containerId: String?
    @Environment(ContainersStore.self) private var store

    var body: some View {
        if let containerId, let container = store.container(withId: containerId) {
            ContainerDetailContent(container: container)
                .id(container.id)
        } else {
            ContentUnavailableView("Select a Container", systemImage: "shippingbox")
        }
    }
}

private struct ContainerDetailContent: View {
    let container: ContainerSnapshot
    @Environment(ContainersStore.self) private var store
    @State private var mode: ContainerDetailMode = .info
    @State private var terminalSessionId = UUID()
    @State private var terminalExited = false
    @State private var showDeleteConfirmation = false
    @State private var showLogs = false

    private var isBusy: Bool {
        store.isBusy(container.id)
    }

    var body: some View {
        Group {
            switch mode {
            case .info: infoForm
            case .terminal: terminalPane
            }
        }
        .navigationTitle(container.id)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("View", selection: $mode) {
                    ForEach(ContainerDetailMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            containerActions
        }
        .onChange(of: mode) {
            if mode == .terminal {
                terminalExited = false
                terminalSessionId = UUID()
            }
        }
        .confirmationDialog(
            "Delete the container “\(container.id)”?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task { await store.delete(id: container.id, force: false) }
            }
            if container.status == .running {
                Button("Force Delete (stops it first)", role: .destructive) {
                    Task { await store.delete(id: container.id, force: true) }
                }
            }
        } message: {
            Text("This permanently removes the container.")
        }
        .sheet(isPresented: $showLogs) {
            LogsSheet(title: "\(container.id) Logs", hasBootLog: true) {
                try await ContainerClient().logs(id: container.id)
            }
        }
    }

    @ViewBuilder
    private var terminalPane: some View {
        if container.status == .running {
            VStack(spacing: 0) {
                EmbeddedTerminalView(
                    executable: CLIRunner.containerBinary,
                    arguments: ["exec", "-t", "-i", container.id, "sh"]
                ) { _ in
                    terminalExited = true
                }
                .id(terminalSessionId)
                if terminalExited {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle").foregroundStyle(.secondary)
                        Text("Session ended.").font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Reconnect") {
                            terminalExited = false
                            terminalSessionId = UUID()
                        }
                    }
                    .padding(8)
                    .background(.bar)
                }
            }
        } else {
            ContentUnavailableView {
                Label("Container Not Running", systemImage: "terminal")
            } description: {
                Text("Start the container to open a shell inside it.")
            } actions: {
                Button("Start") { Task { await store.start(id: container.id) } }
                    .disabled(isBusy || container.status == .stopping)
            }
        }
    }

    private var infoForm: some View {
        Form {
            Section("Status") {
                LabeledContent("Status") {
                    HStack(spacing: 6) {
                        StatusDot(status: container.status)
                        Text(container.status.rawValue.capitalized)
                        if isBusy {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                }
                if let attachment = container.networks.first {
                    LabeledContent("IP Address", value: "\(attachment.ipv4Address)".withoutCIDRSuffix)
                }
                if let started = container.startedDate {
                    LabeledContent("Started", value: started.formatted(.relative(presentation: .named)))
                }
            }
            Section("Image") {
                LabeledContent("Reference", value: container.configuration.image.reference.shortImageReference)
                LabeledContent("Platform", value: "\(container.platform.os)/\(container.platform.architecture)")
            }
            if !container.configuration.labels.isEmpty {
                Section("Labels") {
                    ForEach(container.configuration.labels.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ToolbarContentBuilder
    private var containerActions: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if container.status == .running {
                Button {
                    Task { await store.stop(id: container.id) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop this container")
                .disabled(isBusy)
            } else {
                Button {
                    Task { await store.start(id: container.id) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .help("Start this container")
                .disabled(isBusy || container.status == .stopping)
            }
            Button {
                showLogs = true
            } label: {
                Label("Logs", systemImage: "text.alignleft")
            }
            .help("View container logs")
            Menu {
                if container.status == .running {
                    Button("Kill (SIGKILL)", role: .destructive) {
                        Task { await store.kill(id: container.id) }
                    }
                }
                Button("Delete…", role: .destructive) {
                    showDeleteConfirmation = true
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }
}
