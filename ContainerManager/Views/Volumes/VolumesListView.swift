//
//  VolumesListView.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct VolumesListView: View {
    @Binding var selection: String?
    @Environment(VolumesStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidate: String?

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.volumes, id: \.id) { volume in
                VolumeRow(volume: volume, size: store.sizes[volume.name])
                    .tag(volume.id)
                    .contextMenu {
                        Button("Delete…", role: .destructive) { deleteCandidate = volume.id }
                    }
            }
        }
        .contextMenu { Button(SidebarSection.volumes.newItemLabel) { showCreateSheet = true } }
        .overlay {
            if store.volumes.isEmpty {
                ContentUnavailableView {
                    Label("No Volumes", systemImage: "externaldrive")
                } description: {
                    Text("Create a volume to give containers storage that survives being recreated — ideal for databases.")
                } actions: {
                    Button("New Volume…") { showCreateSheet = true }
                }
            }
        }
        .navigationTitle("Volumes")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showCreateSheet = true
                } label: {
                    Label("New Volume", systemImage: "plus")
                }
                .help("Create a new volume")
            }
        }
        .sheet(isPresented: $showCreateSheet) {
            VolumeCreateSheet()
        }
        .confirmationDialog(
            "Delete the volume “\(deleteCandidate ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                if let id = deleteCandidate { Task { await store.delete(id: id) } }
                deleteCandidate = nil
            }
        } message: {
            Text("This permanently removes the stored data. Deletion only succeeds when no container is using the volume.")
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
        if router.pendingCreate == .volumes {
            showCreateSheet = true
            router.pendingCreate = nil
        }
    }
}

struct VolumeRow: View {
    let volume: VolumeConfiguration
    let size: UInt64?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(volume.name)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    if volume.isAnonymous {
                        Text("Anonymous")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Text(volume.format)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let size {
                Text(Format.bytes(size))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
