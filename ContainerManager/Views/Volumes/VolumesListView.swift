//
//  VolumesListView.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct VolumesListView: View {
    @Binding var selection: Set<String>
    @Environment(VolumesStore.self) private var store
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""

    private var volumes: [VolumeConfiguration] {
        guard !searchText.isEmpty else { return store.volumes }
        return store.volumes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(volumes, id: \.id) { volume in
                VolumeRow(volume: volume, size: store.sizes[volume.name])
                    .tag(volume.id)
                    .draggable(volume.name)
                    .copyable([volume.name])
            }
        }
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(ids)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter volumes")
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
            deleteCandidates.count > 1
                ? "Delete \(deleteCandidates.count) volumes?"
                : "Delete the volume “\(deleteCandidates.first ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                let ids = deleteCandidates
                Task { for id in ids { await store.delete(id: id) } }
                deleteCandidates = []
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
            Button(SidebarSection.volumes.newItemLabel) { showCreateSheet = true }
        } else {
            Button(ids.count > 1 ? "Copy Names" : "Copy Name") { Pasteboard.copy(ids.sorted()) }
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidates = ids }
        }
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
