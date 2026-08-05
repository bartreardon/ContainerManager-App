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
            // Tie identity to the stack so switching selection rebuilds the view with
            // fresh editing state (the name/icon @State is seeded once, in init).
            StackDetailContent(stack: stack)
                .id(stack.name)
        } else {
            ContentUnavailableView("Select a Stack", systemImage: "square.stack.3d.up")
        }
    }
}

/// Which service sheet to present: a new service, or a replacement for an existing one.
private enum ServiceSheetKind: Identifiable {
    case add
    case replace(ContainerSnapshot)

    var id: String {
        switch self {
        case .add: "add"
        case .replace(let service): service.id
        }
    }
}

private struct StackDetailContent: View {
    let stack: Stack
    @Environment(StacksStore.self) private var store
    @State private var showDeleteConfirmation = false
    @State private var showIconPicker = false
    @State private var serviceSheet: ServiceSheetKind?
    @State private var displayName: String
    @State private var icon: String

    init(stack: Stack) {
        self.stack = stack
        _displayName = State(initialValue: stack.displayName == stack.name ? "" : stack.displayName)
        _icon = State(initialValue: stack.icon)
    }

    private var isBusy: Bool {
        store.isBusy(stack.name)
    }

    private func save() {
        StackMetadata.set(stack.name, displayName: displayName, icon: icon)
        Task { await store.refresh() }
    }

    var body: some View {
        Form {
            Section("Appearance") {
                HStack(spacing: 8) {
                    Button {
                        showIconPicker.toggle()
                    } label: {
                        Image(systemName: icon)
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.bordered)
                    .help("Choose an icon")
                    .popover(isPresented: $showIconPicker, arrowEdge: .bottom) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34), spacing: 6)], spacing: 6) {
                            ForEach(StackIcons.all, id: \.self) { symbol in
                                Button {
                                    icon = symbol
                                    save()
                                    showIconPicker = false
                                } label: {
                                    Image(systemName: symbol)
                                        .frame(width: 28, height: 28)
                                        .background(
                                            icon == symbol ? Color.accentColor.opacity(0.25) : .clear,
                                            in: RoundedRectangle(cornerRadius: 6)
                                        )
                                }
                                .buttonStyle(.plain)
                                .help(symbol)
                            }
                        }
                        .padding(10)
                        .frame(width: 264)
                    }

                    TextField("Name", text: $displayName, prompt: Text(stack.name))
                        .onSubmit(save)
                }
            }
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
            Section {
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
                    .contextMenu {
                        Button("Replace…") { serviceSheet = .replace(service) }
                        Button("Remove from Stack", role: .destructive) {
                            Task { await store.removeService(id: service.id, from: stack.name) }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Services")
                    Spacer()
                    Button {
                        serviceSheet = .add
                    } label: {
                        Label("Add Service…", systemImage: "plus")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Add a service to this stack, or re-create one that failed")
                }
            }

            if !stack.volumes.isEmpty {
                Section {
                    ForEach(stack.volumes) { volume in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(volume.name)
                                .fontWeight(.medium)
                            Text(volume.mounts.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text("Volumes")
                } footer: {
                    Text("Named volumes this stack's services mount. Deleting the stack keeps them — remove them from the Volumes section if you want the data gone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
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
        .sheet(item: $serviceSheet) { kind in
            switch kind {
            case .add:
                StackServiceSheet(stackName: stack.name)
            case .replace(let service):
                StackServiceSheet(stackName: stack.name, replacing: service)
            }
        }
        .confirmationDialog(
            "Delete the stack “\(stack.displayName)”?",
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
