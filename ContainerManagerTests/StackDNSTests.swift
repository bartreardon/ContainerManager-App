//
//  StackDNSTests.swift
//  ContainerManagerTests
//

import Testing

@testable import ContainerManager

/// The runtime rejects a whole container over one bad alias, so what's handed to it
/// has to follow its rules: two or more labels, valid characters, no duplicates.
@Suite("StackDNS")
struct StackDNSTests {
    @Test("A service answers to its key under the stack's own subdomain")
    func keyAlias() {
        let settings = StackDNS.settings(stack: "shop", key: "db", defaultDomain: "test")
        #expect(settings.aliases == ["db.shop.test"])
        #expect(settings.searchDomains == ["shop.test", "test"])
    }

    @Test("Without a default domain nothing is set, since the names couldn't resolve")
    func noDefaultDomain() {
        #expect(StackDNS.settings(stack: "shop", key: "db", defaultDomain: nil) == .none)
        #expect(StackDNS.settings(stack: "shop", key: "db", defaultDomain: "") == .none)
    }

    @Test("Extra names follow the key, lowercased and without duplicates")
    func extraNames() {
        let settings = StackDNS.settings(
            stack: "shop", key: "db", extraNames: ["Database", "db", "database", "pg."], defaultDomain: "test.")
        #expect(settings.aliases == ["db.shop.test", "database.shop.test", "pg.shop.test"])
        #expect(settings.searchDomains == ["shop.test", "test"])
    }

    @Test("A name another service answers to is left to that service")
    func takenNames() {
        let settings = StackDNS.settings(
            stack: "shop", key: "cache", extraNames: ["db", "redis"], taken: ["DB"], defaultDomain: "test")
        #expect(settings.aliases == ["cache.shop.test", "redis.shop.test"])
    }

    @Test("Names that can't be DNS names are dropped rather than failing the create")
    func invalidNames() {
        let settings = StackDNS.settings(
            stack: "shop", key: "db", extraNames: ["-bad", "has space", "a..b", "my_db"], defaultDomain: "test")
        #expect(settings.aliases == ["db.shop.test", "my_db.shop.test"])
        #expect(StackDNS.domain(forStack: "-shop", defaultDomain: "test") == nil)
    }

    @Test("Bare names are recovered from a container's aliases")
    func namesFromAliases() {
        let names = StackDNS.names(
            fromAliases: ["db.shop.test", "Database.shop.test.", "api.example.test"],
            searchDomains: ["shop.test", "test"])
        #expect(names == ["db", "database"])
        #expect(StackDNS.names(fromAliases: ["db.shop.test"], searchDomains: []).isEmpty)
    }

    @Test("Recovered names give the same aliases back")
    func roundTrip() {
        let settings = StackDNS.settings(stack: "shop", key: "db", extraNames: ["pg"], defaultDomain: "test")
        let names = StackDNS.names(fromAliases: settings.aliases, searchDomains: settings.searchDomains)
        #expect(names == ["db", "pg"])
    }
}
