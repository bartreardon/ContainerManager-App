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
    ///
    /// `env` entries (`KEY=value`) are applied both ways, since a `.env` file may be
    /// feeding either style of Dockerfile: as `--build-arg` (picked up by matching
    /// `ARG` declarations) and as baked `ENV` defaults on the resulting image.
    /// `forwardSSH` forwards the host's SSH agent into the build, so a Dockerfile can
    /// reach private repositories (`RUN --mount=type=ssh …`) without baking a key in.
    static func build(
        name: String,
        tag: String,
        noCache: Bool = false,
        env: [String] = [],
        forwardSSH: Bool = false,
        onLine: @escaping (String) -> Void
    ) async throws {
        let context = try BuildLibrary.directory(for: name)
        let dockerfile =
            env.isEmpty
            ? try BuildLibrary.dockerfileURL(for: name)
            : try BuildLibrary.writeDockerfileWithEnv(name, defaults: env)

        // --progress plain emits line-oriented step output (no TTY control codes),
        // which is what we render in the log. Default output is a local OCI image.
        var args = ["build", "--progress", "plain", "-f", dockerfile.path, "-t", tag]
        if noCache { args.append("--no-cache") }
        if forwardSSH { args.append(contentsOf: ["--ssh", "default"]) }
        for entry in env {
            args.append(contentsOf: ["--build-arg", entry])
        }
        args.append(context.path)

        let result = try await CLIRunner.run(args, onLine: onLine)
        guard result.exitCode == 0 else {
            throw BuildError(message: "container build exited with code \(result.exitCode).")
        }
    }
}
