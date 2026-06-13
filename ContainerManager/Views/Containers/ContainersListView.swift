//
//  ContainersListView.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct ContainersListView: View {
    @Binding var selection: String?
    @Environment(ContainersStore.self) private var store
    @State private var showCreateSheet = false

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.containers, id: \.id) { container in
                ContainerRow(container: container)
                    .tag(container.id)
            }
        }
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
        .navigationTitle("Containers")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
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
        .errorAlert($store.lastError)
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(5))
            }
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
