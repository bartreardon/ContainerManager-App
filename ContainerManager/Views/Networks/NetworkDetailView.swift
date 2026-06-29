//
//  NetworkDetailView.swift
//  ContainerManager
//

import ContainerResource
import ContainerizationExtras
import SwiftUI

struct NetworkDetailView: View {
    let networkId: String?
    @Environment(NetworksStore.self) private var store

    var body: some View {
        if let networkId, let network = store.network(withId: networkId) {
            NetworkDetailContent(network: network)
        } else {
            ContentUnavailableView("Select a Network", systemImage: "network")
        }
    }
}

private struct NetworkDetailContent: View {
    let network: NetworkResource
    @Environment(NetworksStore.self) private var store
    @State private var showDeleteConfirmation = false

    private var isBusy: Bool {
        store.isBusy(network.id)
    }

    var body: some View {
        Form {
            Section("Network") {
                LabeledContent("Name", value: network.name)
                LabeledContent("Mode", value: network.configuration.mode == .hostOnly ? "Host-only" : "NAT")
                if network.isBuiltin {
                    LabeledContent("Type", value: "Built-in")
                }
                LabeledContent("Created", value: network.creationDate.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Addressing") {
                LabeledContent("IPv4 Subnet", value: "\(network.status.ipv4Subnet)")
                LabeledContent("IPv4 Gateway", value: "\(network.status.ipv4Gateway)")
                if let ipv6 = network.status.ipv6Subnet {
                    LabeledContent("IPv6 Subnet", value: "\(ipv6)")
                }
            }
            if !network.configuration.options.isEmpty {
                Section("Options") {
                    ForEach(network.configuration.options.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help(network.isBuiltin ? "The built-in network cannot be deleted" : "Delete this network")
                .disabled(network.isBuiltin || isBusy)
            }
        }
        .confirmationDialog(
            "Delete the network “\(network.name)”?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task { await store.delete(id: network.id) }
            }
        } message: {
            Text("Deletion only succeeds when no containers are attached.")
        }
    }
}
