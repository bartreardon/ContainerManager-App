//
//  ContainerDetailView.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import SwiftUI
import struct ContainerizationOCI.Platform

struct ContainerDetailView: View {
    let containerId: String?
    @Environment(ContainersStore.self) private var store

    var body: some View {
        if let containerId, let container = store.container(withId: containerId) {
            ContainerDetailContent(container: container)
        } else {
            ContentUnavailableView("Select a Container", systemImage: "shippingbox")
        }
    }
}

private struct ContainerDetailContent: View {
    let container: ContainerSnapshot
    @Environment(ContainersStore.self) private var store
    @State private var showDeleteConfirmation = false
    @State private var showLogs = false

    private var isBusy: Bool {
        store.isBusy(container.id)
    }

    var body: some View {
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
        .navigationTitle(container.id)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if container.status == .running {
                    Button {
                        Task { await store.stop(id: container.id) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Stop this container")
                    .disabled(isBusy)
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
}
