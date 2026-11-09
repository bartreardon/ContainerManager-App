//
//  GitHub.swift
//  ContainerManager
//

import Foundation

/// Minimal GitHub REST client: fetches published releases for a repo.
/// Used for the container tool's updates; the app's own come through Sparkle.
enum GitHub {
    struct Release: Decodable {
        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
            case assets
        }
    }

    struct BadResponse: LocalizedError {
        var errorDescription: String? { "Unexpected response from GitHub." }
    }

    /// Latest release for `owner/repo` (e.g. "apple/container").
    static func latestRelease(repo: String) async throws -> Release {
        try await get("https://api.github.com/repos/\(repo)/releases/latest")
    }

    /// The most recent releases for `owner/repo`, newest first, drafts and prereleases
    /// included.
    static func releases(repo: String, count: Int = 10) async throws -> [Release] {
        try await get("https://api.github.com/repos/\(repo)/releases?per_page=\(count)")
    }

    private static func get<T: Decodable>(_ url: String) async throws -> T {
        var request = URLRequest(url: URL(string: url)!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ContainerManager", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BadResponse()
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
