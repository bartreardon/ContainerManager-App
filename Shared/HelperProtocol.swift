//
//  HelperProtocol.swift
//  Shared between ContainerManager and ContainerManagerHelper.
//

import Foundation
import XPC

nonisolated enum HelperIdentity {
    static let machService = "com.bartreardon.ContainerManager.Helper"
    static let launchDaemonPlist = "com.bartreardon.ContainerManager.Helper.plist"
    static let appIdentifier = "com.bartreardon.ContainerManager"
    static let helperIdentifier = "com.bartreardon.ContainerManager.Helper"
    static let teamIdentifier = "N8GJ2Y5Z9T"
    /// Authorization right every changing request must carry. Defined by the helper with
    /// the system's `is-admin` rule: admins pass without a prompt, anyone else is asked
    /// for an administrator's credentials.
    static let authorizationRight = "com.bartreardon.ContainerManager.manage"

    /// What each side demands of the other's code signature. Debug builds are
    /// development-signed, so there it's this team and the identifier; release builds
    /// must also be Developer ID-signed, so a development build can't drive a shipped helper.
    static func peerRequirement(signingIdentifier: String) -> XPCPeerRequirement {
        #if DEBUG
        return .isFromSameTeam(andMatchesSigningIdentifier: signingIdentifier)
        #else
        let requirement = xpc_dictionary_create_empty()
        xpc_dictionary_set_string(requirement, "team-identifier", teamIdentifier)
        xpc_dictionary_set_string(requirement, "signing-identifier", signingIdentifier)
        xpc_dictionary_set_int64(requirement, "validation-category", 6)  // Developer ID
        return XPCPeerRequirement(lightweightCodeRequirements: XPCDictionary(requirement))
        #endif
    }
}

/// The only things the helper will do. Deliberately narrow: no request names a
/// program, a command line, or a destination path.
nonisolated enum HelperRequest: Codable, Sendable {
    case ping
    /// `authorization` is an `AuthorizationExternalForm`.
    case installPackage(path: String, authorization: Data)
    case uninstallContainer(authorization: Data)
    case createResolver(domain: String, authorization: Data)
    case deleteResolver(domain: String, authorization: Data)
}

nonisolated enum HelperReply: Codable, Sendable {
    case pong(build: String, executablePath: String)
    case done(output: String)
    case failed(message: String)
}
