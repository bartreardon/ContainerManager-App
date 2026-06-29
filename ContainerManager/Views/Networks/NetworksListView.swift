//
//  NetworksListView.swift
//  ContainerManager
//

import ContainerResource
import ContainerizationExtras
import SwiftUI

struct NetworksListView: View {
    @Binding var selection: String?
    @Environment(NetworksStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidate: String?

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.networks, id: \.id) { network in
                NetworkRow(network: network)
                    .tag(network.id)
                    .contextMenu {
                        Button("Delete…", role: .destructive) { deleteCandidate = network.id }
                            .disabled(network.isBuiltin)
                    }
            }
        }
        .contextMenu { Button(SidebarSection.networks.newItemLabel) { showCreateSheet = true } }
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
        .navigationTitle("Networks")
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
            "Delete the network “\(deleteCandidate ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteCandidate { Task { await store.delete(id: id) } }
                deleteCandidate = nil
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
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
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
