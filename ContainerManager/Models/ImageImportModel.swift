//
//  ImageImportModel.swift
//  ContainerManager
//

import Foundation
import Observation

/// Carries a Dockerfile dropped onto the sidebar's "Images" entry across to the
/// Images view, which opens the Build sheet prefilled with it. (A drop directly
/// on the Images pane is handled there without going through this model.)
@Observable
final class ImageImportModel {
    var pendingDockerfile: String?

    /// Reads Dockerfile text from a dropped URL — the file itself, or a
    /// `Dockerfile` inside a dropped folder. Returns nil if neither is readable text.
    static func dockerfile(at url: URL) -> String? {
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let target = isDirectory.boolValue ? url.appendingPathComponent("Dockerfile") : url
        return try? String(contentsOf: target, encoding: .utf8)
    }
}
