//
//  ImageBuilder.swift
//  ContainerManager
//

import Foundation

/// Runs `container build` for a saved build in the ``BuildLibrary``.
///
/// `build` is one of the few operations the app shells out for (via ``CLIRunner``)
/// rather than calling an in-process client: it streams BuildKit progress as plain
/// text lines, which suits a scrolling log better than a structured progress bar.
enum ImageBuilder {
    struct BuildError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Builds the named library entry, tagging the result `tag`. Streams each output
    /// line via `onLine`; throws ``BuildError`` on a non-zero exit.
    static func build(
        name: String,
        tag: String,
        noCache: Bool = false,
        onLine: @escaping (String) -> Void
    ) async throws {
        let dockerfile = try BuildLibrary.dockerfileURL(for: name)
        let context = try BuildLibrary.directory(for: name)

        // --progress plain emits line-oriented step output (no TTY control codes),
        // which is what we render in the log. Default output is a local OCI image.
        var args = ["build", "--progress", "plain", "-f", dockerfile.path, "-t", tag]
        if noCache { args.append("--no-cache") }
        args.append(context.path)

        let result = try await CLIRunner.run(args, onLine: onLine)
        guard result.exitCode == 0 else {
            throw BuildError(message: "container build exited with code \(result.exitCode).")
        }
    }
}
