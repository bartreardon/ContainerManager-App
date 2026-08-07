//
//  VolumesListView.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct VolumesListView: View {
    @Binding var selection: Set<String>
    @Environment(VolumesStore.self) private var store
    @Environment(StacksStore.self) private var stacksStore
    @Environment(WindowRouter.self) private var router
    @State private var showCreateSheet = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""
    // Persisted: a collapsed group springing back open on every launch is exactly the
    // kind of state a Mac app is expected to remember. SceneStorage takes a plain value,
    // so the set is kept as newline-separated names.
    @SceneStorage("volumeCollapsedGroups") private var collapsedGroupsRaw = ""

    private var collapsedGroups: Set<String> {
        Set(collapsedGroupsRaw.split(separator: "\n").map(String.init))
    }
    @State private var labelTargets: Set<String> = []
    @State private var labelText = ""
    @State private var labelRevision = 0

    private var volumes: [VolumeConfiguration] {
        guard !searchText.isEmpty else { return store.volumes }
        return store.volumes.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    /// Volumes bucketed by label, ungrouped last.
    private var groups: [(name: String, volumes: [VolumeConfiguration])] {
        _ = labelRevision  // re-read app-side labels after they're edited
        let stacks = stacksStore.stacks
        let bucketed = Dictionary(grouping: volumes) {
            VolumeGrouping.group(for: $0, stacks: stacks) ?? VolumeGrouping.ungrouped
        }
        return
            bucketed
            .map { (name: $0.key, volumes: $0.value.sorted { $0.name < $1.name }) }
            .sorted { first, second in
                if first.name == VolumeGrouping.ungrouped { return false }
                if second.name == VolumeGrouping.ungrouped { return true }
                return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
            }
    }

    @ViewBuilder
    private func row(_ volume: VolumeConfiguration) -> some View {
        VolumeRow(
            volume: volume, size: store.sizes[volume.name],
            group: VolumeGrouping.group(for: volume, stacks: stacksStore.stacks)
        )
        .tag(volume.id)
            .draggable(volume.name)
            .copyable([volume.name])
    }

    private func expansion(of group: String) -> Binding<Bool> {
        Binding(
            get: { !collapsedGroups.contains(group) },
            set: { expanded in
                var groups = collapsedGroups
                if expanded { groups.remove(group) } else { groups.insert(group) }
                collapsedGroupsRaw = groups.sorted().joined(separator: "\n")
            })
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            let groups = groups
            // Sections would be noise when nothing is grouped yet.
            if groups.count == 1, groups[0].name == VolumeGrouping.ungrouped {
                ForEach(groups[0].volumes, id: \.id) { row($0) }
            } else {
                ForEach(groups, id: \.name) { group in
                    Section(isExpanded: expansion(of: group.name)) {
                        ForEach(group.volumes, id: \.id) { row($0) }
                    } header: {
                        Text("\(group.name) (\(group.volumes.count))")
                            // Fill the row so the whole header is the hit area, and give
                            // it its own menu — otherwise the List's selection menu
                            // applies here and acts on the selection, not the group.
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(.rect)
                            .contextMenu { groupMenu(group) }
                    }
                }
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
            ToolbarItem(placement: .navigation) {
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
        .alert(
            labelTargets.count > 1 ? "Group \(labelTargets.count) Volumes" : "Set Volume Label",
            isPresented: labelBinding
        ) {
            TextField("Label", text: $labelText)
            Button("Set") {
                VolumeMetadata.set(labelText, for: labelTargets)
                labelRevision += 1
                labelTargets = []
            }
            Button("Clear", role: .destructive) {
                VolumeMetadata.set(nil, for: labelTargets)
                labelRevision += 1
                labelTargets = []
            }
            Button("Cancel", role: .cancel) { labelTargets = [] }
        } message: {
            Text("Volumes sharing a label are grouped together in this list.")
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

    private var labelBinding: Binding<Bool> {
        Binding(get: { !labelTargets.isEmpty }, set: { if !$0 { labelTargets = [] } })
    }

    /// Actions for a whole group, so right-clicking a header acts on the group rather
    /// than on whatever happens to be selected.
    @ViewBuilder
    private func groupMenu(_ group: (name: String, volumes: [VolumeConfiguration])) -> some View {
        let names = Set(group.volumes.map(\.name))
        Button("Select All") { selection = names }
        Button("Copy Names") { Pasteboard.copy(names.sorted()) }
        Button(group.name == VolumeGrouping.ungrouped ? "Set Label…" : "Relabel Group…") {
            labelText = group.name == VolumeGrouping.ungrouped ? "" : group.name
            labelTargets = names
        }
        Divider()
        Button("Delete \(names.count) Volume\(names.count == 1 ? "" : "s")…", role: .destructive) {
            deleteCandidates = names
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        if ids.isEmpty {
            Button(SidebarSection.volumes.newItemLabel) { showCreateSheet = true }
        } else {
            Button(ids.count > 1 ? "Copy Names" : "Copy Name") { Pasteboard.copy(ids.sorted()) }
            Button(ids.count > 1 ? "Group \(ids.count) Volumes…" : "Set Label…") {
                // Seed with the existing label when they already agree.
                let existing = Set(ids.map { VolumeMetadata.label(for: $0) ?? "" })
                labelText = existing.count == 1 ? (existing.first ?? "") : ""
                labelTargets = ids
            }
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
    /// The volume's group, shown alongside the format so it's still visible when a
    /// search flattens the sections.
    var group: String?

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
                HStack(spacing: 4) {
                    Text(volume.format)
                    if let group {
                        Text("· \(group)")
                    }
                }
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
