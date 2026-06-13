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
    @State private var showCreateSheet = false

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.networks, id: \.id) { network in
                NetworkRow(network: network)
                    .tag(network.id)
            }
        }
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
        .errorAlert($store.lastError)
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
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
