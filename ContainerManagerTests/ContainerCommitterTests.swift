//
//  ContainerCommitterTests.swift
//  ContainerManagerTests
//

import ContainerResource
import Testing

@testable import ContainerManager

@Suite("ContainerCommitter")
struct ContainerCommitterTests {
    @Test("The suggested reference is the container name under local/, tagged latest")
    func defaultReference() {
        #expect(ContainerCommitter.defaultReference(forContainer: "web") == "local/web:latest")
        #expect(ContainerCommitter.defaultReference(forContainer: "my-app-2") == "local/my-app-2:latest")
    }

    @Test("Characters an image name can't hold become hyphens", arguments: [
        ("My_App.v2", "local/my-app-v2:latest"),
        ("-web-", "local/web:latest"),
        ("a__b..c", "local/a-b-c:latest"),
        ("_", "local/container:latest"),
    ])
    func defaultReferenceSanitizes(id: String, expected: String) {
        #expect(ContainerCommitter.defaultReference(forContainer: id) == expected)
    }

    @Test("Every suggested reference is a valid one", arguments: [
        "web", "My_App.v2", "UPPER", "a..b", "x__y", "-", "café",
    ])
    func defaultReferenceIsValid(id: String) {
        #expect(ContainerCommitter.isValidReference(ContainerCommitter.defaultReference(forContainer: id)))
    }

    @Test("References are checked before running the CLI")
    func validatesReferences() {
        #expect(ContainerCommitter.isValidReference("local/web:latest"))
        #expect(ContainerCommitter.isValidReference("alpine"))
        #expect(ContainerCommitter.isValidReference("registry.example.com:5000/team/app:1.2"))
        #expect(!ContainerCommitter.isValidReference(""))
        #expect(!ContainerCommitter.isValidReference("Local/Web"))
        #expect(!ContainerCommitter.isValidReference("local/web:"))
        #expect(!ContainerCommitter.isValidReference("my app"))
    }

    @Test("Only running or stopped containers can be committed")
    func commitNeedsRunningOrStopped() {
        #expect(ContainerCommitter.canCommit(.running))
        #expect(ContainerCommitter.canCommit(.stopped))
        #expect(!ContainerCommitter.canCommit(.stopping))
        #expect(!ContainerCommitter.canCommit(.unknown))
    }

    @Test("The stored reference is the CLI's last line, past any progress")
    func readsCommittedReference() {
        let output = "Loading tar archive\nUnpacking image\ndocker.io/local/web:latest\n\n"
        #expect(ContainerCommitter.committedReference(fromOutput: output) == "docker.io/local/web:latest")
        #expect(ContainerCommitter.committedReference(fromOutput: "") == nil)
        #expect(ContainerCommitter.committedReference(fromOutput: "Unpacking image\n") == nil)
    }
}
