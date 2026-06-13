//
//  ContainerInstaller.swift
//  ContainerManager
//

import AppKit
import Foundation

/// Downloads the official `container` installer package from GitHub releases and
/// hands it to Installer.app (which verifies the signature and prompts for admin
/// rights). We never run a privileged installer ourselves.
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
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/apple/container/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ContainerManager", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw InstallerError.badResponse
        }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let signed = release.assets.first { $0.name == "container-installer-signed.pkg" }
            ?? release.assets.first { $0.name.hasSuffix("installer-signed.pkg") }
        guard let asset = signed, let url = URL(string: asset.browserDownloadURL) else {
            throw InstallerError.noPackage
        }
        return Release(version: release.tagName, pkgURL: url)
    }

    /// Downloads the package to a temporary `.pkg` file.
    static func download(_ release: Release) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: release.pkgURL)
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

    private struct GitHubRelease: Decodable {
        let tagName: String
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case assets
        }

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }
    }
}
