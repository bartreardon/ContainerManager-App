//
//  main.swift
//  ContainerManagerHelper
//
//  A launchd daemon, registered by the app with SMAppService, that does the few things
//  needing root: installing and removing Apple's container package, and writing the
//  /etc/resolver entries for local DNS.
//

import Foundation
import XPC

guard getuid() == 0, getppid() == 1 else {
    FileHandle.standardError.write(Data("ContainerManagerHelper runs only under launchd.\n".utf8))
    exit(EX_NOPERM)
}

Authorization.defineRightIfNeeded()
let operations = PrivilegedOperations()

let listener = try XPCListener(
    service: HelperIdentity.machService,
    requirement: HelperIdentity.peerRequirement(signingIdentifier: HelperIdentity.appIdentifier)
) { request in
    request.accept { (message: HelperRequest) -> (any Encodable)? in
        operations.perform(message)
    }
}

IdleExit.start(operations: operations)
dispatchMain()
