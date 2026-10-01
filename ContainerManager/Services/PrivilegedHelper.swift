//
//  PrivilegedHelper.swift
//  ContainerManager
//

import AppKit
import Foundation
import os
import Security
import ServiceManagement
import XPC

/// The app's side of `ContainerManagerHelper`: registering it with launchd, and asking it
/// to do the few things that need root.
enum PrivilegedHelper {
    enum Status: Equatable {
        case notRegistered
        /// Registered, waiting for the user to allow it in System Settings.
        case requiresApproval
        case enabled
        case unavailable(String)

        var label: String {
            switch self {
            case .notRegistered: "Not enabled"
            case .requiresApproval: "Waiting for approval in System Settings"
            case .enabled: "Enabled"
            case .unavailable(let reason): reason
            }
        }
    }

    struct HelperFailure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private static let log = Logger(subsystem: "com.bartreardon.ContainerManager", category: "PrivilegedHelper")

    private static var service: SMAppService {
        SMAppService.daemon(plistName: HelperIdentity.launchDaemonPlist)
    }

    static var status: Status {
        switch service.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        // Also what a daemon that has never been registered reports.
        case .notFound: bundlesDaemon ? .notRegistered : .unavailable("Not found in this copy of the app")
        @unknown default: .unavailable("Unknown")
        }
    }

    private static var bundlesDaemon: Bool {
        FileManager.default.fileExists(
            atPath: Bundle.main.bundleURL
                .appending(path: "Contents/Library/LaunchDaemons/\(HelperIdentity.launchDaemonPlist)").path)
    }

    /// Registers the helper on launch, since it's on by default, unless the user has
    /// disabled it in Settings. Doesn't open System Settings: macOS posts its own
    /// notification about the new background item, and Settings shows it awaiting approval.
    /// Turning it off in System Settings instead leaves it registered but not allowed,
    /// which this also leaves alone.
    static func registerByDefault() {
        guard !AppDefaults.helperTurnedOff, status == .notRegistered else { return }
        do {
            try register(openingSettings: false)
        } catch {
            log.error("Couldn't register the helper: \(String(describing: error), privacy: .public)")
        }
    }

    /// Registers the helper. The first time, macOS holds it for the user to allow in
    /// System Settings ▸ General ▸ Login Items & Extensions, which this then opens.
    static func register(openingSettings: Bool = true) throws {
        guard !Bundle.main.bundlePath.contains("/AppTranslocation/") else {
            throw HelperFailure(message: "Move Container Manager to the Applications folder first.")
        }
        do {
            try service.register()
        } catch {
            guard service.status == .requiresApproval else { throw error }
        }
        if openingSettings, service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
    }

    static func unregister() async throws {
        try await service.unregister()
    }

    static func openLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// Makes launchd run the helper from this copy of the app, at this build. Catches a
    /// helper registered from another copy (an older install, a development build) and
    /// one left running from before an update.
    nonisolated static func ensureCurrent() async {
        guard SMAppService.daemon(plistName: HelperIdentity.launchDaemonPlist).status == .enabled else { return }
        let expectedPath = Bundle.main.bundleURL
            .appending(path: "Contents/MacOS/ContainerManagerHelper").resolvingSymlinksInPath().path
        let expectedBuild = Bundle.main.infoDictionary?["CFBundleVersion"] as? String
        let reply = try? await send(.ping)
        if case .pong(let build, let path)? = reply,
            build == expectedBuild,
            URL(fileURLWithPath: path).resolvingSymlinksInPath().path == expectedPath
        {
            return
        }
        let daemon = SMAppService.daemon(plistName: HelperIdentity.launchDaemonPlist)
        try? await daemon.unregister()
        try? daemon.register()
    }

    // MARK: Requests

    nonisolated static func installPackage(at url: URL) async throws -> String {
        try await authorized { try await perform(.installPackage(path: url.path, authorization: $0)) }
    }

    nonisolated static func uninstallContainer() async throws {
        _ = try await authorized { try await perform(.uninstallContainer(authorization: $0)) }
    }

    nonisolated static func createResolver(domain: String) async throws {
        _ = try await authorized { try await perform(.createResolver(domain: domain, authorization: $0)) }
    }

    nonisolated static func deleteResolver(domain: String) async throws {
        _ = try await authorized { try await perform(.deleteResolver(domain: domain, authorization: $0)) }
    }

    private nonisolated static func perform(_ request: HelperRequest) async throws -> String {
        switch try await send(request) {
        case .done(let output): return output
        case .failed(let message): throw HelperFailure(message: message)
        case .pong: throw HelperFailure(message: "The helper gave an unexpected reply.")
        }
    }

    /// One session per request: the helper exits when idle, and a fresh session is
    /// simpler than reviving one it left behind.
    private nonisolated static func send(_ request: HelperRequest) async throws -> HelperReply {
        let session = try XPCSession(
            machService: HelperIdentity.machService,
            options: .privileged,
            requirement: HelperIdentity.peerRequirement(signingIdentifier: HelperIdentity.helperIdentifier))
        defer { session.cancel(reason: "Request complete") }
        return try await withCheckedThrowingContinuation { continuation in
            do {
                try session.send(request) { result in
                    switch result {
                    case .success(let message):
                        do {
                            continuation.resume(returning: try message.decode(as: HelperReply.self))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: Authorization

    /// Runs `body` with proof, for the helper, that this user may make the change.
    /// Administrators pass without a prompt; anyone else is asked for an administrator's
    /// name and password. The reference stays alive until the helper has used it.
    private nonisolated static func authorized<T>(_ body: (Data) async throws -> T) async throws -> T {
        // The helper defines the right when it starts. Before that, an undefined right
        // falls back to a rule that prompts even administrators.
        if AuthorizationRightGet(HelperIdentity.authorizationRight, nil) != errAuthorizationSuccess {
            _ = try await send(.ping)
        }

        var authRef: AuthorizationRef?
        guard AuthorizationCreate(nil, nil, [], &authRef) == errAuthorizationSuccess, let authRef else {
            throw HelperFailure(message: "Couldn't start an authorization session.")
        }
        defer { AuthorizationFree(authRef, []) }

        let status = HelperIdentity.authorizationRight.withCString { name in
            var item = AuthorizationItem(name: name, valueLength: 0, value: nil, flags: 0)
            return withUnsafeMutablePointer(to: &item) { itemPointer in
                var rights = AuthorizationRights(count: 1, items: itemPointer)
                return AuthorizationCopyRights(
                    authRef, &rights, nil, [.interactionAllowed, .extendRights, .preAuthorize], nil)
            }
        }
        switch status {
        case errAuthorizationSuccess: break
        case errAuthorizationCanceled: throw CancellationError()
        default: throw HelperFailure(message: "An administrator needs to approve this change.")
        }

        var form = AuthorizationExternalForm()
        guard AuthorizationMakeExternalForm(authRef, &form) == errAuthorizationSuccess else {
            throw HelperFailure(message: "Couldn't pass the authorization to the helper.")
        }
        let data = withUnsafeBytes(of: &form) { Data($0) }
        return try await body(data)
    }
}
