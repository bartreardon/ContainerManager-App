//
//  ContainersListView.swift
//  ContainerManager
//

import AppKit
import ContainerResource
import SwiftUI
import UniformTypeIdentifiers

struct ContainersListView: View {
    @Binding var selection: Set<String>
    @Environment(ContainersStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""
    @State private var exportStatus: String?
    @SceneStorage("containerCollapsedGroups") private var collapsedGroups = ""

    private var containers: [ContainerSnapshot] {
        guard !searchText.isEmpty else { return store.containers }
        return store.containers.filter {
            $0.id.localizedCaseInsensitiveContains(searchText)
                || $0.configuration.image.reference.localizedCaseInsensitiveContains(searchText)
        }
    }

    @ViewBuilder
    private func row(_ container: ContainerSnapshot) -> some View {
        ContainerRow(container: container)
            .tag(container.id)
            .draggable(container.id)
            .copyable([container.id])
    }

    /// Containers bucketed by the stack they belong to; standalone ones last.
    private var groups: [(name: String, items: [ContainerSnapshot])] {
        let bucketed = Dictionary(grouping: containers) {
            $0.configuration.labels[StackLabels.stack] ?? ListGroups.ungrouped
        }
        return ListGroups.sorted(
            bucketed.map { (name: $0.key, items: $0.value.sorted { $0.id < $1.id }) })
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            let groups = groups
            // Sections would be noise when nothing belongs to a stack.
            if groups.count == 1, groups[0].name == ListGroups.ungrouped {
                ForEach(groups[0].items, id: \.id) { row($0) }
            } else {
                ForEach(groups, id: \.name) { group in
                    let expanded = ListGroups.expansion(of: group.name, collapsed: $collapsedGroups)
                    Section {
                        if expanded.wrappedValue {
                            ForEach(group.items, id: \.id) { row($0) }
                        }
                    } header: {
                        GroupHeader(name: group.name, count: group.items.count, isExpanded: expanded)
                            .contextMenu { groupMenu(group) }
                    }
                }
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter containers")
        .overlay(alignment: .bottom) {
            if let exportStatus {
                BusyBanner(text: exportStatus)
            }
        }
        .animation(.default, value: exportStatus)
        .overlay {
            if store.containers.isEmpty {
                ContentUnavailableView {
                    Label("No Containers", systemImage: "shippingbox")
                } description: {
                    Text("Create a container from an image, or start one with the container CLI.")
                } actions: {
                    Button("New Container…") { showCreateSheet = true }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Container", systemImage: "plus")
                }
                .help("Create a new container")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            ContainerCreateSheet()
        }
        .confirmationDialog(
            deleteCandidates.count > 1
                ? "Delete \(deleteCandidates.count) containers?"
                : "Delete the container “\(deleteCandidates.first ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                let ids = deleteCandidates
                Task { for id in ids { await store.delete(id: id, force: true) } }
                deleteCandidates = []
            }
        } message: {
            Text("This permanently removes the container.")
        }
        .errorAlert($store.lastError)
        .onAppear(perform: consumeCreate)
        .onChange(of: router.pendingCreate) { consumeCreate() }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: AppDefaults.listRefresh)
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { !deleteCandidates.isEmpty }, set: { if !$0 { deleteCandidates = [] } })
    }

    /// Acts on the whole group. Without this the List's selection menu applies to a
    /// header right-click and treats the group's name as an item id.
    @ViewBuilder
    private func groupMenu(_ group: (name: String, items: [ContainerSnapshot])) -> some View {
        let ids = Set(group.items.map(\.id))
        let running = group.items.filter { $0.status == .running }.map(\.id)
        Button("Select All") { selection = ids }
        Button("Copy Names") { Pasteboard.copy(ids.sorted()) }
        if running.count < ids.count {
            Button("Start") { Task { for id in ids { await store.start(id: id) } } }
        }
        if !running.isEmpty {
            Button("Stop") { Task { for id in running { await store.stop(id: id) } } }
        }
        Divider()
        Button("Delete \(ids.count) Container\(ids.count == 1 ? "" : "s")…", role: .destructive) {
            deleteCandidates = ids
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        if ids.isEmpty {
            Button(SidebarSection.containers.newItemLabel) { showCreateSheet = true }
        } else {
            let running = ids.filter { store.container(withId: $0)?.status == .running }
            if running.count < ids.count {
                Button("Start") { Task { for id in ids { await store.start(id: id) } } }
            }
            if !running.isEmpty {
                Button("Stop") { Task { for id in running { await store.stop(id: id) } } }
            }
            if ids.count == 1, let id = ids.first, store.container(withId: id)?.status == .running {
                Button("Open Terminal") { router.openTerminal(id: id, in: .containers) }
                Button("Open in Terminal.app") { openInTerminalApp(id) }
            }
            Button(ids.count > 1 ? "Copy Names" : "Copy Name") { Pasteboard.copy(ids.sorted()) }
            if ids.count == 1, let id = ids.first {
                Button("Export Filesystem…") { export(id) }
                    .disabled(exportStatus != nil)
            }
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidates = ids }
        }
    }

    private func openInTerminalApp(_ id: String) {
        Task {
            store.lastError = TerminalLauncher.presentedError(
                for: await TerminalLauncher.openContainerShell(containerId: id))
        }
    }

    /// Saves the container's filesystem as a tar archive (container 1.2.1+).
    private func export(_ id: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(id).tar"
        panel.allowedContentTypes = [UTType("public.tar-archive")].compactMap { $0 }
        panel.message = "Export “\(id)” filesystem as a tar archive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        exportStatus = "Exporting “\(id)”…"
        Task {
            do {
                try await ContainerExporter.export(id: id, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                store.lastError = PresentedError(title: "Export failed", error: error)
            }
            exportStatus = nil
        }
    }

    private func consumeCreate() {
        if router.pendingCreate == .containers {
            showCreateSheet = true
            router.pendingCreate = nil
        }
    }
}

struct ContainerRow: View {
    let container: ContainerSnapshot

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: container.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(container.id)
                    .fontWeight(.medium)
                Text(container.configuration.image.reference.shortImageReference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let attachment = container.networks.first {
                Text("\(attachment.ipv4Address)".withoutCIDRSuffix)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
