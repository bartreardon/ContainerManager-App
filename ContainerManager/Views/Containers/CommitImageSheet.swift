//
//  CommitImageSheet.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import SwiftUI

/// Which container a Commit to Image… menu item was chosen for, and its state then.
struct CommitRequest: Identifiable {
    let containerId: String
    let status: RuntimeStatus
    var id: String { containerId }

    init(_ container: ContainerSnapshot) {
        containerId = container.id
        status = container.status
    }
}

/// Saves a container's filesystem as a new local image (`container commit`, 1.6.0+).
/// The only choice `commit` offers is the image reference, so that's all this asks.
struct CommitImageSheet: View {
    let request: CommitRequest
    private var containerId: String { request.containerId }
    private var status: RuntimeStatus { request.status }

    @Environment(\.dismiss) private var dismiss
    @Environment(ImagesStore.self) private var imagesStore
    @Environment(WindowRouter.self) private var router
    @Environment(SystemStore.self) private var systemStore

    @State private var reference = ""
    /// Lets the field be checked against existing images, which are listed normalized.
    @State private var config: ContainerSystemConfig?
    @State private var isCommitting = false
    /// Held so Cancel can stop the work rather than only closing the sheet.
    @State private var task: Task<Void, Never>?
    @State private var committedReference: String?
    @State private var error: PresentedError?

    private var derivedReference: String { ContainerCommitter.defaultReference(forContainer: containerId) }
    private var effectiveReference: String {
        let r = reference.trimmingCharacters(in: .whitespaces)
        return r.isEmpty ? derivedReference : r
    }
    private var isValid: Bool { ContainerCommitter.isValidReference(effectiveReference) }

    /// The reference as the image will be listed (registry and tag filled in).
    private var normalizedReference: String? {
        guard let config else { return nil }
        return try? ClientImage.normalizeReference(effectiveReference, containerSystemConfig: config)
    }
    private var replacesExisting: Bool {
        guard let normalizedReference else { return false }
        return imagesStore.images.contains { $0.reference == normalizedReference }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Image reference", text: $reference, prompt: Text(derivedReference))
                    if !isValid {
                        Text("Use a name like local/my-app:latest: lowercase letters, digits, and . _ - / separators, with an optional :tag.")
                            .font(.caption)
                            .foregroundStyle(.red)
                    } else if replacesExisting && committedReference == nil {
                        Label("An image with this name already exists. Committing moves the name to the new image.", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                } header: {
                    Text("Commit “\(containerId)” to an Image")
                } footer: {
                    Text(behaviourNote)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let error {
                    Section {
                        Text(error.message)
                            .foregroundStyle(.red)
                            .font(.callout)
                            .textSelection(.enabled)
                    }
                }
                if let committedReference {
                    Section {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Committed \(committedReference.shortImageReference)")
                                .font(.callout)
                        }
                        Button("Show in Images") {
                            dismiss()
                            router.select(id: committedReference, in: .images)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .disabled(isCommitting)

            Divider()

            HStack(spacing: 12) {
                if isCommitting {
                    ProgressView().controlSize(.small)
                    Text("Committing…").font(.caption)
                }
                Spacer()
                Button(committedReference == nil ? "Cancel" : "Done") {
                    task?.cancel()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                if committedReference == nil {
                    Button("Commit") { task = Task { await commit() } }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            isCommitting || !isValid || !ContainerCommitter.canCommit(status)
                                || !systemStore.serviceSupports(ContainerVersion.commit))
                }
            }
            .padding(14)
        }
        .frame(width: 480)
        .task {
            config = try? await imagesStore.systemConfig()
            await imagesStore.refresh()
        }
        .onDisappear { task?.cancel() }
    }

    /// What happens to the container, and what the image does and doesn't include.
    private var behaviourNote: String {
        let state =
            switch status {
            case .running:
                "“\(containerId)” keeps running. Its filesystem is frozen for a moment while its disk is copied, so writes inside it wait until that's done."
            case .stopped:
                "“\(containerId)” is stopped, so its filesystem is saved as it was left."
            default:
                "“\(containerId)” must be running or stopped to commit."
            }
        return state
            + " Only the container's own filesystem is saved: volumes, folders shared from your Mac and tmpfs mounts aren't. The image runs the container's command, with its environment, working directory, user and labels."
    }

    private func commit() async {
        isCommitting = true
        error = nil
        let target = effectiveReference
        do {
            var stored = try await ContainerCommitter.commit(id: containerId, reference: target)
            await imagesStore.refresh()
            // The CLI prints the stored reference; if it didn't, list it as Images does.
            if !imagesStore.images.contains(where: { $0.reference == stored }), let normalizedReference {
                stored = normalizedReference
            }
            committedReference = stored
            OperationNotice.finished(
                "Committed \(stored.shortImageReference)", detail: "The image is ready to use.",
                succeeded: true, section: .images, item: stored)
        } catch is CancellationError {
            // Asked for — the sheet is already closing.
        } catch {
            self.error = PresentedError(title: "Commit failed", error: error)
            OperationNotice.finished(
                "Commit of \(containerId)", detail: PresentedError.describe(error),
                succeeded: false, section: .containers)
        }
        isCommitting = false
    }
}
