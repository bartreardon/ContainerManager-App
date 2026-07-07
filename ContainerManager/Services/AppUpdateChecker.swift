//
//  AppUpdateChecker.swift
//  ContainerManager
//

import Foundation

/// Checks GitHub for a newer ContainerManager release. The app doesn't self-update
/// (no helper tool); the "update" action just opens the release page for a manual
/// download, so this only needs the version tag and the page URL.
enum AppUpdateChecker {
    static let repo = "bartreardon/ContainerManager-App"
    static let releasesPage = URL(string: "https://github.com/\(repo)/releases/latest")!

    /// The running app's marketing version (CFBundleShortVersionString).
    static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    struct Release {
        let version: String
        let pageURL: URL
    }

    static func latestRelease() async throws -> Release {
        let release = try await GitHub.latestRelease(repo: repo)
        return Release(version: release.tagName, pageURL: release.htmlURL)
    }
}
