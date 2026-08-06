//
//  EnvFile.swift
//  ContainerManager
//

import AppKit
import Foundation

/// Reads `.env`-style files (the format `docker run --env-file` accepts) into the
/// `KEY=value` lines the app uses for container env and image build args.
enum EnvFile {
    /// Parses env-file text into `KEY=value` entries.
    ///
    /// Skips blank lines and `#` comments, tolerates a leading `export `, and strips
    /// matching surrounding quotes. Inline `#` is kept — like Docker, it's part of the
    /// value, not a comment.
    static func parse(_ text: String) -> [String] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if line.hasPrefix("export ") {
                line = String(line.dropFirst("export ".count)).trimmingCharacters(in: .whitespaces)
            }
            guard let separator = line.firstIndex(of: "=") else { return nil }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { return nil }

            var value = String(line[line.index(after: separator)...]).trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let first = value.first, value.last == first, first == "\"" || first == "'" {
                value = String(value.dropFirst().dropLast())
            }
            return "\(key)=\(value)"
        }
    }

    /// Prompts for an env file and returns its contents. Env files are usually named
    /// `.env` with no extension, so any file is selectable.
    @MainActor
    static func pick() throws -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.message = "Choose an env file (KEY=value per line)"
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return try String(contentsOf: url, encoding: .utf8)
    }
}
