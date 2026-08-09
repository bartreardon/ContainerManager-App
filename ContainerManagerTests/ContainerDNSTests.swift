//
//  ContainerDNSTests.swift
//  ContainerManagerTests
//

import Testing

@testable import ContainerManager

/// The TOML editing here writes to a file the user owns and may have put their own
/// settings in, so "everything except our one key survives" is the property that
/// matters. The domain validation guards a string interpolated into a command run with
/// administrator rights, so it's worth pinning too.
@Suite("ContainerDNS")
struct ContainerDNSTests {
    // MARK: Reading

    @Test("Domain list drops the header")
    func parsesDomains() {
        #expect(ContainerDNS.parseDomains("DOMAIN\ntest\n") == ["test"])
        #expect(ContainerDNS.parseDomains("DOMAIN\n") == [])
        #expect(ContainerDNS.parseDomains("") == [])
        #expect(ContainerDNS.parseDomains("DOMAIN\ntest\nlocal.dev\n") == ["test", "local.dev"])
    }

    @Test("The default domain is read from the [dns] table only")
    func parsesDefaultDomain() {
        let toml = """
            [container]
            cpus = 4

            [dns]
            domain = "test"

            [registry]
            domain = "docker.io"
            """
        #expect(ContainerDNS.parseDefaultDomain(toml) == "test")
        // The registry table has a `domain` too — picking that one up would be wrong.
        #expect(ContainerDNS.parseDefaultDomain("[registry]\ndomain = \"docker.io\"") == nil)
        #expect(ContainerDNS.parseDefaultDomain("[dns]") == nil)
        #expect(ContainerDNS.parseDefaultDomain("") == nil)
    }

    // MARK: State

    @Test("A domain is only active when both halves agree")
    func stateReflectsBothHalves() {
        let active = ContainerDNS.State(resolverDomains: ["test"], defaultDomain: "test")
        #expect(active.isActive)
        #expect(active.isIncomplete == false)

        // The state you land in by following the tutorial and stopping early.
        let created = ContainerDNS.State(resolverDomains: ["test"], defaultDomain: nil)
        #expect(created.isActive == false)
        #expect(created.isIncomplete)

        // Configured, but macOS won't route to it.
        let unrouted = ContainerDNS.State(resolverDomains: [], defaultDomain: "test")
        #expect(unrouted.isActive == false)
        #expect(unrouted.isIncomplete)

        let nothing = ContainerDNS.State()
        #expect(nothing.isActive == false)
        #expect(nothing.isIncomplete == false)
    }

    // MARK: Writing

    @Test("Setting a domain in an empty file creates the table")
    func writesIntoEmptyFile() {
        #expect(ContainerDNS.setting(domain: "test", in: "") == "[dns]\ndomain = \"test\"\n")
    }

    @Test("An existing [dns] table is updated in place")
    func updatesExistingTable() {
        let before = "[dns]\ndomain = \"old\"\n"
        #expect(ContainerDNS.setting(domain: "new", in: before) == "[dns]\ndomain = \"new\"\n")
    }

    @Test("Other tables and unknown keys survive untouched")
    func preservesTheRestOfTheFile() {
        let before = """
            # my settings
            [container]
            cpus = 8
            memory = "4g"

            [dns]
            domain = "old"
            somethingElse = true

            [registry]
            domain = "ghcr.io"
            """
        let after = ContainerDNS.setting(domain: "test", in: before)
        #expect(after.contains("# my settings"))
        #expect(after.contains("cpus = 8"))
        #expect(after.contains("somethingElse = true"))
        #expect(after.contains("[registry]\ndomain = \"ghcr.io\""))
        #expect(after.contains("[dns]\ndomain = \"test\""))
        #expect(after.contains("\"old\"") == false)
        #expect(ContainerDNS.parseDefaultDomain(after) == "test")
    }

    @Test("A [dns] table without a domain gains one")
    func insertsIntoEmptyTable() {
        let after = ContainerDNS.setting(domain: "test", in: "[dns]\n\n[registry]\ndomain = \"x\"")
        #expect(ContainerDNS.parseDefaultDomain(after) == "test")
        #expect(after.contains("[registry]"))
    }

    @Test("Clearing removes only the domain line")
    func clearingRemovesTheKey() {
        let before = "[container]\ncpus = 8\n\n[dns]\ndomain = \"test\"\n"
        let after = ContainerDNS.setting(domain: nil, in: before)
        #expect(ContainerDNS.parseDefaultDomain(after) == nil)
        #expect(after.contains("cpus = 8"))
        #expect(after.contains("[dns]"))
    }

    @Test("Adding to a file with no [dns] table keeps what's there")
    func appendsTable() {
        let after = ContainerDNS.setting(domain: "test", in: "[container]\ncpus = 8\n")
        #expect(after.contains("cpus = 8"))
        #expect(ContainerDNS.parseDefaultDomain(after) == "test")
    }

    @Test("Setting then clearing round-trips")
    func roundTrips() {
        let original = "[container]\ncpus = 8\n"
        let set = ContainerDNS.setting(domain: "test", in: original)
        let cleared = ContainerDNS.setting(domain: nil, in: set)
        #expect(ContainerDNS.parseDefaultDomain(cleared) == nil)
        #expect(cleared.contains("cpus = 8"))
    }

    // MARK: Validation

    @Test(
        "Valid domains are accepted",
        arguments: ["test", "local.dev", "my-domain", "a1.b2.c3"])
    func acceptsValidDomains(domain: String) {
        #expect(ContainerDNS.isValidDomain(domain))
    }

    /// These go into a shell command run with administrator rights, so anything that
    /// could end the quoting or chain another command has to be refused outright.
    @Test(
        "Anything that could break out of the command is refused",
        arguments: [
            "", "test; rm -rf /", "test'", "test\"", "test$(whoami)", "test`id`", "test |cat",
            "test\nmore", "-test", "test-", ".test", "test.", "te st",
        ])
    func refusesUnsafeDomains(domain: String) {
        #expect(ContainerDNS.isValidDomain(domain) == false)
    }
}
