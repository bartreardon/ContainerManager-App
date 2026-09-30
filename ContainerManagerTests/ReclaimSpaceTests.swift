//
//  ReclaimSpaceTests.swift
//  ContainerManagerTests
//

import Testing

@testable import ContainerManager

@Suite("ReclaimSpace")
struct ReclaimSpaceTests {
    /// What a container created under container 1.2.x reports under 1.4.1.
    static let olderAgentFailure = """
        failed to clean container: failed to clean container code-server-web (cause: "internalError: \
        "failed to clean mounts in code-server-web: / (internalError: "filesystemOperation trim failed"), \
        /config (notFound: "failed to stat path")"")
        """

    @Test("A container from before container 1.4.1 is told to re-create")
    func recognisesOlderAgent() {
        #expect(ReclaimSpace.isFromOlderAgent(Self.olderAgentFailure))
    }

    @Test("Other failures are left as they are")
    func leavesOtherFailures() {
        #expect(!ReclaimSpace.isFromOlderAgent("cannot clean: container is not running"))
        #expect(!ReclaimSpace.isFromOlderAgent("failed to clean container: XPC connection interrupted"))
    }

    @Test("The explanation names the container, the fix, and keeps the details")
    func explanation() {
        let message = ReclaimSpace.NeedsRecreating(containerID: "code-server-web", details: "trim failed")
            .errorDescription ?? ""
        #expect(message.contains("“code-server-web”"))
        #expect(message.contains("Re-create the container"))
        #expect(message.hasSuffix("Details: trim failed"))
    }
}
