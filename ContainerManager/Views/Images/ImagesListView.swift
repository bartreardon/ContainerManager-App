//
//  ImagesListView.swift
//  ContainerManager
//

import ContainerAPIClient
import SwiftUI

/// A request to open the Build sheet, optionally prefilled with a Dockerfile
/// (from the toolbar/empty-state buttons, or a dropped/imported file).
private struct BuildRequest: Identifiable {
    let id = UUID()
    var dockerfile: String?
}

struct ImagesListView: View {
    @Binding var selection: String?
    @Environment(ImagesStore.self) private var store
    @Environment(ImageImportModel.self) private var imageImport
    @Environment(WindowRouter.self) private var router
    @State private var showPullSheet = false
    @State private var buildRequest: BuildRequest?
    @State private var dropTargeted = false
    @State private var deleteCandidate: String?

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.images, id: \.reference) { image in
                ImageRow(image: image, size: store.sizes[image.digest])
                    .tag(image.reference)
                    .contextMenu {
                        Button("Delete…", role: .destructive) { deleteCandidate = image.reference }
                    }
            }
        }
        .contextMenu { Button(SidebarSection.images.newItemLabel) { buildRequest = BuildRequest() } }
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
        .navigationTitle("Images")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    buildRequest = BuildRequest()
                } label: {
                    Label("Build Image", systemImage: "hammer")
                }
                .help("Build an image from a Dockerfile")
            }
            ToolbarItem(placement: .primaryAction) {
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
            "Delete the image “\(deleteCandidate?.shortImageReference ?? "")”?",
            isPresented: deleteBinding
        ) {
            Button("Delete", role: .destructive) {
                if let reference = deleteCandidate { Task { await store.delete(reference: reference) } }
                deleteCandidate = nil
            }
        } message: {
            Text("This removes the image from local storage.")
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
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
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

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(image.reference.shortImageReference)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Text(image.digest.shortDigest)
                    .font(.caption.monospaced())
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
            .navigationTitle(image.reference.shortImageReference)
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
