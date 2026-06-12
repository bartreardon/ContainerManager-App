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
    ///
    /// Tries AppleScript first, which triggers the system's automation consent prompt
    /// on first use. If consent is denied, falls back to opening a .command file with
    /// Terminal, which requires no automation permission.
    static func openMachineShell(machineId: String) async -> ShellResult {
        // Machine ids are restricted to [a-z0-9-]; the binary path is shell-quoted.
        let command = "'\(CLIRunner.containerBinary)' machine run --name \(machineId)"

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
            try await openCommandFile(named: "container-shell-\(machineId)", command: command)
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
