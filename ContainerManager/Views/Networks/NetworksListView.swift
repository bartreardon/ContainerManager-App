//
//  NetworksListView.swift
//  ContainerManager
//

import ContainerResource
import ContainerizationExtras
import SwiftUI

struct NetworksListView: View {
    @Binding var selection: Set<String>
    @Environment(NetworksStore.self) private var store
    @Environment(StacksStore.self) private var stacksStore
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""
    @SceneStorage("networkCollapsedGroups") private var collapsedGroups = ""

    private var networks: [NetworkResource] {
        guard !searchText.isEmpty else { return store.networks }
        return store.networks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private func row(_ network: NetworkResource) -> some View {
        NetworkRow(network: network)
            .tag(network.id)
            .draggable(network.name)
            .copyable([network.name])
    }

    /// Networks bucketed by the stack that created them — from the stack label where
    /// there is one, falling back to the `<stack>-net` name for networks made before
    /// that label was written.
    private var groups: [(name: String, items: [NetworkResource])] {
        let byNetworkName = Dictionary(
            stacksStore.stacks.map { ($0.networkName, $0.name) }, uniquingKeysWith: { first, _ in first })
        let bucketed = Dictionary(grouping: networks) { network in
            network.labels[StackLabels.stack] ?? byNetworkName[network.name] ?? ListGroups.ungrouped
        }
        return ListGroups.sorted(
            bucketed.map { (name: $0.key, items: $0.value.sorted { $0.name < $1.name }) })
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            let groups = groups
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
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter networks")
        .overlay {
            if store.networks.isEmpty {
                ContentUnavailableView {
                    Label("No Networks", systemImage: "network")
                } description: {
                    Text("Create a network to connect containers, or use the built-in default network.")
                } actions: {
                    Button("New Network…") { showCreateSheet = true }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Network", systemImage: "plus")
                }
                .help("Create a new network")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            NetworkCreateSheet()
        }
        .confirmationDialog(
            deleteCandidates.count > 1
                ? "Delete \(deleteCandidates.count) networks?"
                : "Delete the network “\(deleteCandidates.first ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                let ids = deleteCandidates
                Task { for id in ids { await store.delete(id: id) } }
                deleteCandidates = []
            }
        } message: {
            Text("Deletion only succeeds when no containers are attached.")
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
    private func groupMenu(_ group: (name: String, items: [NetworkResource])) -> some View {
        let ids = Set(group.items.map(\.id))
        let deletable = Set(group.items.filter { !$0.isBuiltin }.map(\.id))
        Button("Select All") { selection = ids }
        Button("Copy Names") { Pasteboard.copy(group.items.map(\.name).sorted()) }
        Divider()
        Button("Delete \(deletable.count) Network\(deletable.count == 1 ? "" : "s")…", role: .destructive) {
            deleteCandidates = deletable
        }
        .disabled(deletable.isEmpty)
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        if ids.isEmpty {
            Button(SidebarSection.networks.newItemLabel) { showCreateSheet = true }
        } else {
            let deletable = ids.filter { store.network(withId: $0)?.isBuiltin == false }
            Button(ids.count > 1 ? "Copy Names" : "Copy Name") { Pasteboard.copy(ids.sorted()) }
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidates = deletable }
                .disabled(deletable.isEmpty)
        }
    }

    private func consumeCreate() {
        if router.pendingCreate == .networks {
            showCreateSheet = true
            router.pendingCreate = nil
        }
    }
}

struct NetworkRow: View {
    let network: NetworkResource

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "network")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(network.name)
                        .fontWeight(.medium)
                    if network.isBuiltin {
                        Text("Built-in")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(network.configuration.mode == .hostOnly ? "Host-only" : "NAT")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: "\(network.status.ipv4Subnet)")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
