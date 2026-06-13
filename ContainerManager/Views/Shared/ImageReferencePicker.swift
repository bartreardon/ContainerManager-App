//
//  ImageReferencePicker.swift
//  ContainerManager
//

import ContainerAPIClient
import SwiftUI

/// An editable image-reference field: free text plus a menu of locally
/// available images for quick selection.
struct ImageReferencePicker: View {
    let label: String
    @Binding var reference: String
    var prompt: String = "e.g. alpine:3.22"

    @Environment(ImagesStore.self) private var imagesStore

    var body: some View {
        HStack(spacing: 6) {
            TextField(label, text: $reference, prompt: Text(prompt))
            if !imagesStore.images.isEmpty {
                Menu {
                    Section("Local Images") {
                        ForEach(imagesStore.images, id: \.reference) { image in
                            Button(image.reference.shortImageReference) {
                                reference = image.reference.shortImageReference
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Choose a downloaded image")
            }
        }
        .task {
            if imagesStore.images.isEmpty {
                await imagesStore.refresh()
            }
        }
    }
}
