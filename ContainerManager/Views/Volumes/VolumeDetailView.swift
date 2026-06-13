//
//  VolumeDetailView.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct VolumeDetailView: View {
    let volumeName: String?
    @Environment(VolumesStore.self) private var store

    var body: some View {
        if let volumeName, let volume = store.volume(withId: volumeName) {
            VolumeDetailContent(volume: volume)
        } else {
            ContentUnavailableView("Select a Volume", systemImage: "externaldrive")
        }
    }
}

private struct VolumeDetailContent: View {
    let volume: VolumeConfiguration
    @Environment(VolumesStore.self) private var store
    @State private var showDeleteConfirmation = false

    private var isBusy: Bool {
        store.isBusy(volume.id)
    }

    var body: some View {
        Form {
            Section("Volume") {
                LabeledContent("Name", value: volume.name)
                LabeledContent("Driver", value: volume.driver)
                LabeledContent("Format", value: volume.format)
                if volume.isAnonymous {
                    LabeledContent("Type", value: "Anonymous")
                }
                if let size = store.sizes[volume.name] {
                    LabeledContent("Size", value: Format.bytes(size))
                }
                LabeledContent("Created", value: volume.creationDate.formatted(date: .abbreviated, time: .shortened))
            }
            Section("Storage") {
                LabeledContent("Host Path") {
                    Text(volume.source)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .multilineTextAlignment(.trailing)
                }
            }
            if !volume.options.isEmpty {
                Section("Options") {
                    ForEach(volume.options.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        LabeledContent(key, value: value)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(volume.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .help("Delete this volume")
                .disabled(isBusy)
            }
        }
        .confirmationDialog(
            "Delete the volume “\(volume.name)”?",
            isPresented: $showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task { await store.delete(id: volume.id) }
            }
        } message: {
            Text("This permanently removes the stored data. Deletion only succeeds when no container is using the volume.")
        }
    }
}
