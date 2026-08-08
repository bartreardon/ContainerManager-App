//
//  TerminalLauncher.swift
//  ContainerManager
//

import AppKit
import Foundation

enum TerminalLauncher {
    enum ShellResult {
        case opened
        /// Opened via the .command fallback because Terminal automation consent is denied.
        case openedViaFallback
        /// Automation consent is denied and the fallback failed too.
        case automationDenied
        case failed(String)
    }

    /// errAEEventNotPermitted — the user (or a missing prompt) denied Apple Events to Terminal.
    private static let notPermittedErrorCode = -1743

    /// Opens an interactive shell to the given machine in Terminal.app.
    /// The failure to show for `result`, or nil when a terminal opened.
    ///
    /// Lives here because every caller reported the same two failures in the same
    /// words, and a launch that opened via the fallback is still a launch.
    static func presentedError(for result: ShellResult) -> PresentedError? {
        switch result {
        case .opened, .openedViaFallback:
            nil
        case .automationDenied:
            PresentedError(
                title: "Terminal access needed",
                message:
                    "Enable ContainerManager under Automation in Privacy & Security settings, then try again."
            )
        case .failed(let message):
            PresentedError(title: "Failed to open Terminal", message: message)
        }
    }

    static func openMachineShell(machineId: String) async -> ShellResult {
        await openShell(
            command: "'\(CLIRunner.containerBinary)' machine run --name \(machineId)",
            fallbackName: "container-shell-\(machineId)"
        )
    }

    /// Opens an interactive shell inside the given running container in Terminal.app.
    static func openContainerShell(containerId: String) async -> ShellResult {
        await openShell(
            command: "'\(CLIRunner.containerBinary)' exec -t -i \(containerId) sh",
            fallbackName: "container-exec-\(containerId)"
        )
    }

    /// Runs `command` in Terminal.app. Tries AppleScript first, which triggers the
    /// system's automation consent prompt on first use; if consent is denied, falls
    /// back to opening a .command file with Terminal, which needs no automation.
    ///
    /// `command` is interpolated into AppleScript source and, on the fallback path, a
    /// shell script. That is safe only because the ids reaching it come from the
    /// runtime and are restricted to a name charset by `ManagedContainer.nameValid`
    /// upstream — nothing here escapes them. If names are ever allowed quotes,
    /// backslashes or semicolons, this becomes an injection point needing escaping on
    /// both paths.
    private static func openShell(command: String, fallbackName: String) async -> ShellResult {
        let script = """
            tell application "Terminal"
                activate
                do script "\(command)"
            end tell
            """
        if let appleScript = NSAppleScript(source: script) {
            var errorInfo: NSDictionary?
            appleScript.executeAndReturnError(&errorInfo)
            guard let errorInfo else {
                return .opened
            }
            let code = errorInfo[NSAppleScript.errorNumber] as? Int
            if code != Self.notPermittedErrorCode {
                let message = errorInfo[NSAppleScript.errorMessage] as? String
                return .failed(message ?? "AppleScript error \(code.map(String.init) ?? "unknown")")
            }
        }

        do {
            try await openCommandFile(named: fallbackName, command: command)
            return .openedViaFallback
        } catch {
            return .automationDenied
        }
    }

    /// Opens the Automation pane of Privacy & Security settings so the user can
    /// re-enable Terminal control for this app.
    static func openAutomationSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private static func openCommandFile(named name: String, command: String) async throws {
        guard let terminal = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Terminal") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).command")
        let contents = """
            #!/bin/zsh
            clear
            exec \(command)
            """
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        _ = try await NSWorkspace.shared.open(
            [url],
            withApplicationAt: terminal,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
