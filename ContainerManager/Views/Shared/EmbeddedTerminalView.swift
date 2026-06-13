//
//  EmbeddedTerminalView.swift
//  ContainerManager
//

import AppKit
import SwiftTerm
import SwiftUI

/// An in-app terminal that runs a local command in a real pseudo-terminal.
/// Used to open an interactive shell into a container machine via `container machine run`,
/// which requires a TTY — LocalProcessTerminalView provides one.
struct EmbeddedTerminalView: NSViewRepresentable {
    /// Absolute path to the executable to run (the resolved `container` CLI).
    let executable: String
    /// Arguments, e.g. ["machine", "run", "--name", "dev"].
    let arguments: [String]
    /// Working directory for the spawned process. For `container machine run` this
    /// should be the macOS home directory so the machine maps it to the shared
    /// `/Users/<user>` (matching Terminal.app); otherwise the machine falls back
    /// to its own `/home/<user>`.
    var workingDirectory: String? = nil
    /// Called when the spawned process exits, with its exit code.
    var onTerminated: (Int32?) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTerminated: onTerminated)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let view = LocalProcessTerminalView(frame: .zero)
        view.processDelegate = context.coordinator

        // Inherit the app's environment but force a sensible TERM and locale for the PTY.
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = "xterm-256color"
        if environment["LANG"] == nil {
            environment["LANG"] = "en_US.UTF-8"
        }
        let environmentList = environment.map { "\($0.key)=\($0.value)" }

        view.startProcess(
            executable: executable,
            args: arguments,
            environment: environmentList,
            currentDirectory: workingDirectory
        )
        return view
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        context.coordinator.onTerminated = onTerminated
    }

    final class Coordinator: NSObject, LocalProcessTerminalViewDelegate {
        var onTerminated: (Int32?) -> Void

        init(onTerminated: @escaping (Int32?) -> Void) {
            self.onTerminated = onTerminated
        }

        func processTerminated(source: TerminalView, exitCode: Int32?) {
            onTerminated(exitCode)
        }

        func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: LocalProcessTerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    }
}
