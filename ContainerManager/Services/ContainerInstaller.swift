//
//  ContainerInstaller.swift
//  ContainerManager
//

import AppKit
import Foundation

/// Downloads the official `container` installer package from GitHub releases. The
/// privileged helper installs it after checking it's Apple's notarized package; without
/// the helper it goes to Installer.app, which checks and asks for admin rights itself.
enum ContainerInstaller {
    static let releasesPage = URL(string: "https://github.com/apple/container/releases/latest")!

    struct Release {
        let version: String
        let pkgURL: URL
    }

    enum InstallerError: LocalizedError {
        case noPackage
        case badResponse

        var errorDescription: String? {
            switch self {
            case .noPackage: "No signed installer package was found in the latest release."
            case .badResponse: "Unexpected response from GitHub."
            }
        }
    }

    /// Resolves the latest release and its signed `.pkg` asset.
    static func latestRelease() async throws -> Release {
        let release = try await GitHub.latestRelease(repo: "apple/container")
        let signed = release.assets.first { $0.name == "container-installer-signed.pkg" }
            ?? release.assets.first { $0.name.hasSuffix("installer-signed.pkg") }
        guard let asset = signed else {
            throw InstallerError.noPackage
        }
        return Release(version: release.tagName, pkgURL: asset.browserDownloadURL)
    }

    /// Downloads the package to a temporary `.pkg` file, calling `progress` with the
    /// fraction done (0–1) as it arrives, from a background thread.
    static func download(
        _ release: Release, progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(
            from: release.pkgURL, delegate: DownloadProgress(progress))
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallerError.badResponse
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("container-installer-\(release.version).pkg")
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }

    /// Opens the package in Installer.app.
    @MainActor
    static func launchInstaller(pkg: URL) {
        NSWorkspace.shared.open(pkg)
    }
}

/// Watches a download task's progress and reports it in whole-percent steps, so the
/// interface isn't updated for every packet.
private nonisolated final class DownloadProgress: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let report: @Sendable (Double) -> Void
    private var observation: NSKeyValueObservation?
    private var lastPercent = -1

    init(_ report: @escaping @Sendable (Double) -> Void) {
        self.report = report
    }

    func urlSession(_ session: URLSession, didCreateTask task: URLSessionTask) {
        observation = task.progress.observe(\.fractionCompleted) { [weak self] progress, _ in
            guard let self else { return }
            let percent = Int(progress.fractionCompleted * 100)
            guard percent != lastPercent else { return }
            lastPercent = percent
            report(progress.fractionCompleted)
        }
    }
}
