//
//  StackDetailView.swift
//  ContainerManager
//

import AppKit
import ContainerResource
import SwiftUI

struct StackDetailView: View {
    let stackName: String?
    @Environment(StacksStore.self) private var store

    var body: some View {
        if let stackName, let stack = store.stack(named: stackName) {
            StackDetailContent(stack: stack)
        } else {
            ContentUnavailableView("Select a Stack", systemImage: "square.stack.3d.up")
        }
    }
}

private struct StackDetailContent: View {
    let stack: Stack
    @Environment(StacksStore.self) private var store
    @State private var showDeleteConfirmation = false

    private var isBusy: Bool {
        store.isBusy(stack.name)
    }

    var body: some View {
        Form {
            if let url = stack.webURL {
                Section("Web") {
                    LabeledContent("Address") {
                        Link(url.absoluteString, destination: url)
                    }
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open in Browser", systemImage: "safari")
                    }
                    .disabled(!stack.anyRunning)
                }
            }
            Section("Services") {
                ForEach(stack.services, id: \.id) { service in
                    HStack(spacing: 8) {
                        StatusDot(status: service.status)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(service.configuration.labels[StackLabels.role] ?? service.id)
                                .fontWeight(.medium)
                            Text(service.configuration.image.reference.shortImageReference)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer()
                        if let attachment = service.networks.first {
                            Text("\(attachment.ipv4Address)".withoutCIDRSuffix)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(stack.name)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if stack.allRunning {
                    Button {
                        Task { await store.stop(name: stack.name) }
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                    .help("Stop all services")
                    .disabled(isBusy)
                } else {
                    Button {
                        Task { await store.start(name: stack.name) }
                    } label: {
                        Label("Start", systemImage: "play.fill")
                    }
                    .help("Start all services")
                    .disabled(isBusy)
                }
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete the whole stack")
                .disabled(isBusy)
            }
        }
        .confirmationDialog(
            "Delete the stack “\(stack.name)”?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task { await store.delete(name: stack.name) }
            }
        } message: {
            Text("Removes all \(stack.services.count) containers and the stack network. Data volumes are kept — delete them from the Volumes section if you want them gone.")
        }
    }
}
