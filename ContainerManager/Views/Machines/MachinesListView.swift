//
//  MachinesListView.swift
//  ContainerManager
//

import ContainerResource
import MachineAPIClient
import SwiftUI

struct MachinesListView: View {
    @Binding var selection: String?
    @Environment(MachinesStore.self) private var store
    @State private var showCreateSheet = false

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.machines, id: \.id) { machine in
                MachineRow(machine: machine, isDefault: machine.id == store.defaultId)
                    .tag(machine.id)
            }
        }
        .overlay {
            if store.machines.isEmpty {
                ContentUnavailableView {
                    Label("No Machines", systemImage: "desktopcomputer")
                } description: {
                    Text("Create a container machine to get a persistent Linux environment that feels like part of your Mac.")
                } actions: {
                    Button("New Machine…") { showCreateSheet = true }
                }
            }
        }
        .navigationTitle("Machines")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Machine", systemImage: "plus")
                }
                .help("Create a new container machine")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            MachineCreateSheet()
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

struct MachineRow: View {
    let machine: MachineSnapshot
    let isDefault: Bool

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: machine.status)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(machine.id)
                        .fontWeight(.medium)
                    if isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                            .help("Default machine")
                    }
                }
                Text(machine.configuration.image.reference.shortImageReference)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if let ip = machine.ipAddress {
                Text(ip)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
