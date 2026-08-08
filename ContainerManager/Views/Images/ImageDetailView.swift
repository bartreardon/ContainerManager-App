//
//  ImageDetailView.swift
//  ContainerManager
//

import ContainerAPIClient
import SwiftUI

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
