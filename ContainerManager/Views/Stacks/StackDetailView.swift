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
    @Environment(NetworksStore.self) private var networksStore
    @Environment(WindowRouter.self) private var router
    @State private var showDeleteConfirmation = false
    @State private var showIconPicker = false
    @State private var serviceSheet: ServiceSheetKind?
    @State private var repairProgress = GuiProgress()
    @State private var showLog = false
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

    /// Services in the stack's saved definition that aren't present — usually one that
    /// failed to create.
    private var missing: [StackServiceSpec] {
        store.missingServices(in: stack)
    }

    private func save() {
        StackMetadata.set(stack.name, displayName: displayName, icon: icon)
        Task { await store.refresh() }
    }

    private func openInTerminalApp(_ id: String) {
        Task {
            store.lastError = TerminalLauncher.presentedError(
                for: await TerminalLauncher.openContainerShell(containerId: id))
        }
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
                    .disabled(!stack.webIsRunning)
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
                    // The whole row is the target, not just the text drawn in it —
                    // otherwise right-clicking the gap between the name and the address
                    // hits nothing, which is not how the row looks.
                    .contentShape(.rect)
                    .contextMenu {
                        // A stack service is a normal container, so `exec` works — and
                        // the shell sees the stack's volumes mounted.
                        Button("Open Terminal") {
                            router.openTerminal(id: service.id, in: .containers)
                        }
                        .disabled(service.status != .running)
                        Button("Open in Terminal.app") { openInTerminalApp(service.id) }
                            .disabled(service.status != .running)
                        Divider()
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

            if !missing.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(missing.count) service\(missing.count == 1 ? "" : "s") missing")
                                .fontWeight(.medium)
                            Text(missing.map(\.key).joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isBusy {
                            ProgressView().controlSize(.small)
                        } else {
                            Button("Re-create") {
                                Task { await store.recreateMissingServices(in: stack, progress: repairProgress) }
                            }
                        }
                    }
                } footer: {
                    Text("These are defined in the stack's saved definition but aren't running. Re-creating uses the settings it was created with.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent("Name", value: stack.networkName)
                if let network = networksStore.network(withId: stack.networkName) {
                    LabeledContent("Mode", value: network.configuration.mode == .hostOnly ? "Host-only" : "NAT")
                    LabeledContent("IPv4 Subnet", value: "\(network.status.ipv4Subnet)")
                } else {
                    LabeledContent("Status", value: "Not created yet")
                }
            } header: {
                Text("Network")
            } footer: {
                Text("Services reach each other by IP on this network. It's internal to this Mac — to reach a service from another device, publish a port on the service and use this Mac's address.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
                // Both stay put and enable/disable, rather than one swapping into the
                // other. A stack is often *partly* running — a one-shot init service
                // exits by design — and swapping meant Stop never appeared for those
                // at all, since they can never be "all running".
                Button {
                    Task { await store.start(name: stack.name) }
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .help("Start any services that aren’t running")
                .disabled(isBusy || stack.allRunning)
                Button {
                    Task { await store.stop(name: stack.name) }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .help("Stop the services that are running")
                .disabled(isBusy || !stack.anyRunning)
                if isBusy {
                    ProgressView().controlSize(.small)
                }
                if StackLog.exists(for: stack.name) {
                    Button {
                        showLog = true
                    } label: {
                        Label("Log", systemImage: "doc.text")
                    }
                    .help("How this stack was created, and anything the import couldn’t carry over")
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
        .sheet(isPresented: $showLog) {
            StackLogSheet(stackName: stack.name)
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
