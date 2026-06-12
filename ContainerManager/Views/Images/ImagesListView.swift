//
//  ImagesListView.swift
//  ContainerManager
//

import ContainerAPIClient
import SwiftUI

struct ImagesListView: View {
    @Binding var selection: String?
    @Environment(ImagesStore.self) private var store
    @State private var showPullSheet = false

    var body: some View {
        @Bindable var store = store
        List(selection: $selection) {
            ForEach(store.images, id: \.reference) { image in
                ImageRow(image: image, size: store.sizes[image.digest])
                    .tag(image.reference)
            }
        }
        .overlay {
            if store.images.isEmpty {
                ContentUnavailableView {
                    Label("No Images", systemImage: "opticaldiscdrive")
                } description: {
                    Text("Pull an image from a registry to use it for containers and machines.")
                } actions: {
                    Button("Pull Image…") { showPullSheet = true }
                }
            }
        }
        .navigationTitle("Images")
        .toolbar {
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
        .errorAlert($store.lastError)
        .task {
            while !Task.isCancelled {
                await store.refresh()
                try? await Task.sleep(for: .seconds(10))
            }
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
        } else {
            ContentUnavailableView("Select an Image", systemImage: "opticaldiscdrive")
        }
    }
}
