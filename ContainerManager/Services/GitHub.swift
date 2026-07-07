//
//  GitHub.swift
//  ContainerManager
//

import Foundation

/// Minimal GitHub REST client: fetches the latest published release for a repo.
/// Shared by the container-tool and app update checks.
enum GitHub {
    struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
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
            case htmlURL = "html_url"
            case assets
        }
    }

    struct BadResponse: LocalizedError {
        var errorDescription: String? { "Unexpected response from GitHub." }
    }

    /// Latest release for `owner/repo` (e.g. "apple/container").
    static func latestRelease(repo: String) async throws -> Release {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("ContainerManager", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw BadResponse()
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }
}
