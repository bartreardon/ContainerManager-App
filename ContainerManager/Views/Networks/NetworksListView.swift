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
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""

    private var networks: [NetworkResource] {
        guard !searchText.isEmpty else { return store.networks }
        return store.networks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(networks, id: \.id) { network in
                NetworkRow(network: network)
                    .tag(network.id)
                    .draggable(network.name)
                    .copyable([network.name])
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
            ToolbarItem(placement: .primaryAction) {
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
