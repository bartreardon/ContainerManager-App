//
//  ImagesListView.swift
//  ContainerManager
//

import AppKit
import ContainerAPIClient
import ContainerResource
import MachineAPIClient
import SwiftUI
import UniformTypeIdentifiers

/// A request to open the Build sheet, optionally prefilled with a Dockerfile
/// (from the toolbar/empty-state buttons, or a dropped/imported file).
private struct BuildRequest: Identifiable {
    let id = UUID()
    var dockerfile: String?
}

struct ImagesListView: View {
    @Binding var selection: Set<String>
    @Environment(ImagesStore.self) private var store
    @Environment(ContainersStore.self) private var containersStore
    @Environment(MachinesStore.self) private var machinesStore
    @Environment(ImageImportModel.self) private var imageImport
    @Environment(WindowRouter.self) private var router
    @State private var showPullSheet = false
    @State private var buildRequest: BuildRequest?
    @State private var dropTargeted = false
    @State private var deleteCandidates: Set<String> = []
    @State private var searchText = ""
    @State private var archiveStatus: String?
    @SceneStorage("imageCollapsedGroups") private var collapsedGroups = ""

    private var images: [ClientImage] {
        guard !searchText.isEmpty else { return store.images }
        return store.images.filter { $0.reference.localizedCaseInsensitiveContains(searchText) }
    }

    @ViewBuilder
    private func row(_ image: ClientImage) -> some View {
        ImageRow(
            image: image, size: store.sizes[image.digest],
            isUnused: !usedReferences.contains(image.reference)
        )
        .tag(image.reference)
        .draggable(image.reference)
        .copyable([image.reference])
    }

    /// What refers to each image reference: the stack a container belongs to, or the
    /// containers/machines bucket for standalone ones.
    private var owners: [String: Set<String>] {
        var owners: [String: Set<String>] = [:]
        for container in containersStore.containers {
            let owner = container.configuration.labels[StackLabels.stack] ?? "Containers"
            owners[container.configuration.image.reference, default: []].insert(owner)
        }
        for machine in machinesStore.machines {
            owners[machine.configuration.image.reference, default: []].insert("Machines")
        }
        return owners
    }

    /// Images bucketed by what uses them. An image used by more than one thing goes to
    /// a single "Shared" group rather than being listed twice — a row has to stay
    /// uniquely identifiable for selection to work.
    private var groups: [(name: String, items: [ClientImage])] {
        let owners = owners
        let bucketed = Dictionary(grouping: images) { image -> String in
            let users = owners[image.reference] ?? []
            switch users.count {
            case 0: return ListGroups.unused
            case 1: return users.first ?? ListGroups.unused
            default: return ListGroups.shared
            }
        }
        return ListGroups.sorted(
            bucketed.map { (name: $0.key, items: $0.value.sorted { $0.reference < $1.reference }) })
    }

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            let groups = groups
            if groups.count == 1 {
                ForEach(groups[0].items, id: \.reference) { row($0) }
            } else {
                ForEach(groups, id: \.name) { group in
                    let expanded = ListGroups.expansion(of: group.name, collapsed: $collapsedGroups)
                    Section {
                        if expanded.wrappedValue {
                            ForEach(group.items, id: \.reference) { row($0) }
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
        .searchable(text: $searchText, placement: .sidebar, prompt: "Filter images")
        .overlay(alignment: .bottom) {
            if let archiveStatus {
                BusyBanner(text: archiveStatus)
            }
        }
        .animation(.default, value: archiveStatus)
        .overlay {
            if store.images.isEmpty {
                ContentUnavailableView {
                    Label("No Images", systemImage: "opticaldiscdrive")
                } description: {
                    Text("Pull an image from a registry, or build one from a Dockerfile — drag a Dockerfile here to start a build.")
                } actions: {
                    Button("Pull Image…") { showPullSheet = true }
                    Button("Build Image…") { buildRequest = BuildRequest() }
                }
            }
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [6]))
                    .padding(4)
                    .allowsHitTesting(false)
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let text = ImageImportModel.dockerfile(at: url) else { return false }
            buildRequest = BuildRequest(dockerfile: text)
            return true
        } isTargeted: { dropTargeted = $0 }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    buildRequest = BuildRequest()
                } label: {
                    Label("Build Image", systemImage: "hammer")
                }
                .help("Build an image from a Dockerfile")
            }
            ToolbarItem(placement: .navigation) {
                Button {
                    showPullSheet = true
                } label: {
                    Label("Pull Image", systemImage: "square.and.arrow.down")
                }
                .help("Pull an image from a registry")
            }
        }
        .sheet(isPresented: $showPullSheet) {
            ImagePullSheet()
        }
        .sheet(item: $buildRequest) { request in
            BuildImageSheet(initialDockerfile: request.dockerfile)
        }
        .confirmationDialog(
            deleteCandidates.count > 1
                ? "Delete \(deleteCandidates.count) images?"
                : "Delete the image “\(deleteCandidates.first?.shortImageReference ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                let refs = deleteCandidates
                Task { for reference in refs { await store.delete(reference: reference) } }
                deleteCandidates = []
            }
        } message: {
            Text("This removes the image\(deleteCandidates.count > 1 ? "s" : "") from local storage.")
        }
        .errorAlert($store.lastError)
        .onAppear {
            consumePendingImport()
            consumeCreate()
        }
        .onChange(of: imageImport.pendingDockerfile) { consumePendingImport() }
        .onChange(of: router.pendingCreate) { consumeCreate() }
        .task {
            while !Task.isCancelled {
                await store.refresh()
                // Those two stores are refreshed by their own lists, which aren't on
                // screen here — without this the "Unused" badges would go stale.
                await containersStore.refresh()
                await machinesStore.refresh()
                try? await Task.sleep(for: AppDefaults.listRefresh)
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { !deleteCandidates.isEmpty }, set: { if !$0 { deleteCandidates = [] } })
    }

    /// Acts on the whole group. Without this the List's selection menu applies to a
    /// header right-click and treats the group's name as an item reference — which read
    /// as "Delete the image “Unused”".
    @ViewBuilder
    private func groupMenu(_ group: (name: String, items: [ClientImage])) -> some View {
        let references = group.items.map(\.reference).sorted()
        Button("Select All") { selection = Set(references) }
        Button("Copy References") { Pasteboard.copy(references) }
        Button("Save \(references.count) Image\(references.count == 1 ? "" : "s") as Archive…") {
            saveArchive(references)
        }
        .disabled(archiveStatus != nil)
        Divider()
        Button("Delete \(references.count) Image\(references.count == 1 ? "" : "s")…", role: .destructive) {
            deleteCandidates = Set(references)
        }
    }

    @ViewBuilder
    private func rowMenu(_ ids: Set<String>) -> some View {
        if ids.isEmpty {
            Button(SidebarSection.images.newItemLabel) { buildRequest = BuildRequest() }
            Button("Load from Archive…") { loadArchive() }
                .disabled(archiveStatus != nil)
            Divider()
            Button("Delete Unused Images…", role: .destructive) {
                deleteCandidates = Set(unusedReferences)
            }
            .disabled(unusedReferences.isEmpty)
        } else {
            Button(ids.count > 1 ? "Copy References" : "Copy Reference") { Pasteboard.copy(ids.sorted()) }
            Button(ids.count > 1 ? "Save \(ids.count) Images as Archive…" : "Save as Archive…") {
                saveArchive(Array(ids).sorted())
            }
            .disabled(archiveStatus != nil)
            Divider()
            Button("Delete…", role: .destructive) { deleteCandidates = ids }
        }
    }

    /// Writes the selected images to an OCI archive — layers and configuration, so it
    /// can be loaded back here or on another Mac.
    private func saveArchive(_ references: [String]) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue =
            references.count == 1
            ? "\(references[0].shortImageReference.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")).tar"
            : "images.tar"
        panel.allowedContentTypes = [UTType("public.tar-archive")].compactMap { $0 }
        panel.message = "Save \(references.count) image\(references.count == 1 ? "" : "s") as an OCI archive"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        archiveStatus = "Saving \(references.count) image\(references.count == 1 ? "" : "s")…"
        Task {
            do {
                try await ImageArchiver.save(references: references, to: url)
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } catch {
                store.lastError = PresentedError(title: "Couldn’t save archive", error: error)
            }
            archiveStatus = nil
        }
    }

    private func loadArchive() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType("public.tar-archive")].compactMap { $0 }
        panel.message = "Choose an OCI image archive to load"
        panel.prompt = "Load"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        archiveStatus = "Loading images from \(url.lastPathComponent)…"
        Task {
            do {
                try await ImageArchiver.load(from: url)
                await store.refresh()
            } catch {
                store.lastError = PresentedError(title: "Couldn’t load archive", error: error)
            }
            archiveStatus = nil
        }
    }

    /// Image references in use by a container (running or not) or a machine. Anything
    /// else is safe to remove; the store has already filtered out the runtime's own
    /// builder and init images, so nothing here is a system image.
    private var usedReferences: Set<String> {
        var used = Set(containersStore.containers.map { $0.configuration.image.reference })
        used.formUnion(machinesStore.machines.map { $0.configuration.image.reference })
        return used
    }

    private var unusedReferences: [String] {
        images.map(\.reference).filter { !usedReferences.contains($0) }
    }

    /// Picks up a Dockerfile dropped on the sidebar's Images entry.
    private func consumePendingImport() {
        guard let text = imageImport.pendingDockerfile else { return }
        buildRequest = BuildRequest(dockerfile: text)
        imageImport.pendingDockerfile = nil
    }

    /// New ▸ Image (menu/context) opens the Build sheet.
    private func consumeCreate() {
        if router.pendingCreate == .images {
            buildRequest = BuildRequest()
            router.pendingCreate = nil
        }
    }
}

struct ImageRow: View {
    let image: ClientImage
    let size: Int64?
    /// Not referenced by any container or machine, so removing it frees real space.
    var isUnused = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(image.reference.shortImageReference)
                    .fontWeight(.medium)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Text(image.digest.shortDigest)
                        .font(.caption.monospaced())
                    if isUnused {
                        Text("Unused")
                            .font(.caption2)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
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

struct ImageDetailView: View {
    let reference: String?
    @Environment(ImagesStore.self) private var store
    @State private var showDeleteConfirmation = false
    @State private var showContainerCreate = false
    @State private var showMachineCreate = false

    var body: some View {
        if let reference, let image = store.images.first(where: { $0.reference == reference }) {
            Form {
                Section("Image") {
                    LabeledContent("Reference", value: image.reference)
                    LabeledContent("Digest", value: image.digest)
                    if let size = store.sizes[image.digest] {
                        LabeledContent("Size", value: Format.bytes(size))
                    }
                }
                Section("Use Image") {
                    Button {
                        showContainerCreate = true
                    } label: {
                        Label("Run Container from Image", systemImage: "shippingbox")
                    }
                    Button {
                        showMachineCreate = true
                    } label: {
                        Label("Create Machine from Image", systemImage: "desktopcomputer")
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
                    .help("Delete this image")
                }
            }
            .confirmationDialog(
                "Delete the image “\(image.reference.shortImageReference)”?",
                isPresented: $showDeleteConfirmation
            ) {
                Button("Delete", role: .destructive) {
                    Task { await store.delete(reference: image.reference) }
                }
            } message: {
                Text("This removes the image from local storage.")
            }
            .sheet(isPresented: $showContainerCreate) {
                ContainerCreateSheet(initialImage: image.reference.shortImageReference)
            }
            .sheet(isPresented: $showMachineCreate) {
                MachineCreateSheet(initialImage: image.reference.shortImageReference)
            }
        } else {
            ContentUnavailableView("Select an Image", systemImage: "opticaldiscdrive")
        }
    }
}
