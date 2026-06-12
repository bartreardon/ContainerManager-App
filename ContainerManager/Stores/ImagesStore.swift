//
//  ImagesStore.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerPersistence
import Foundation
import Observation

@Observable
final class ImagesStore {
    private(set) var images: [ClientImage] = []
    /// Sizes keyed by image digest, computed lazily after each refresh.
    private(set) var sizes: [String: Int64] = [:]
    var lastError: PresentedError?

    private var cachedConfig: ContainerSystemConfig?

    func systemConfig() async throws -> ContainerSystemConfig {
        if let cachedConfig {
            return cachedConfig
        }
        let config = try await ConfigurationLoader.load()
        cachedConfig = config
        return config
    }

    func refresh() async {
        do {
            let config = try await systemConfig()
            let list = try await ClientImage.list().filter { image in
                !Utility.isInfraImage(
                    name: image.reference,
                    builderImage: config.build.image,
                    initImage: config.vminit.image
                )
            }
            images = list.sorted { $0.reference < $1.reference }
            await updateSizes()
        } catch {
            lastError = PresentedError(title: "Failed to load images", error: error)
        }
    }

    func pull(reference: String, progress: GuiProgress) async throws {
        let config = try await systemConfig()
        _ = try await ClientImage.pull(
            reference: reference,
            scheme: .auto,
            containerSystemConfig: config,
            progressUpdate: progress.handler
        )
        await refresh()
    }

    func delete(reference: String) async {
        do {
            try await ClientImage.delete(reference: reference)
            await refresh()
        } catch {
            lastError = PresentedError(title: "Failed to delete image", error: error)
        }
    }

    private func updateSizes() async {
        for image in images where sizes[image.digest] == nil {
            if let size = try? await ClientImage.getFullImageSize(image: image) {
                sizes[image.digest] = size
            }
        }
    }
}
