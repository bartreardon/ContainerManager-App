//
//  FleetComposeImportTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// Anchors `Bundle(for:)` on the test bundle so the fixture can be found.
private final class BundleAnchor {}

/// Imports Fleet's own `docker-compose.yml` — the one their deploy guide tells you to
/// download, kept here verbatim as a fixture.
///
/// This is the compose file the lab walkthrough is built on, and it exercises nearly
/// everything the importer does at once: service references, `${VAR}` fields, health
/// check conditions, long and short port forms, relative bind mounts, an x86 platform
/// pin, and a one-shot init container. If an upstream change or a change here breaks
/// that walkthrough, this is where it shows up.
@Suite("Fleet compose import")
struct FleetComposeImportTests {
    private func importedDocument() throws -> StackTemplateDocument {
        let bundle = Bundle(for: BundleAnchor.self)
        let url = try #require(
            bundle.url(forResource: "fleet-docker-compose", withExtension: "yml"),
            "fixture missing from the test bundle")
        return try ComposeImporter.document(at: url)
    }

    private func service(_ document: StackTemplateDocument, _ key: String) throws
        -> StackTemplateDocument.Service
    {
        try #require(document.services.first { $0.key == key })
    }

    @Test("Every service imports, in dependency order")
    func servicesAndOrder() throws {
        let document = try importedDocument()
        #expect(Set(document.services.map(\.key)) == ["mysql", "redis", "fleet-init", "fleet"])
        // fleet depends on all three, so it must be created last.
        let order = document.services.map(\.key)
        #expect(order.last == "fleet")
    }

    @Test("Fleet's references to mysql and redis become address tokens")
    func serviceReferencesRewritten() throws {
        let env = try service(importedDocument(), "fleet").env ?? []
        #expect(env.contains("FLEET_MYSQL_ADDRESS=${IP:mysql}:3306"))
        #expect(env.contains("FLEET_REDIS_ADDRESS=${IP:redis}:6379"))
    }

    @Test("The x86 platform pin is normalised to OCI spelling")
    func platformNormalised() throws {
        // fleetdm/fleet publishes no arm64 image, so this one runs emulated.
        #expect(try service(importedDocument(), "fleet").platform == "linux/amd64")
    }

    @Test("Compose variables become fields, with secrets masked")
    func variablesBecomeFields() throws {
        let document = try importedDocument()
        let keys = Set(document.fields.map(\.key))
        for expected in [
            "name", "MYSQL_ROOT_PASSWORD", "MYSQL_PASSWORD", "FLEET_SERVER_PRIVATE_KEY",
            "FLEET_SERVER_PORT",
        ] {
            #expect(keys.contains(expected), "missing field \(expected)")
        }
        for secret in ["MYSQL_ROOT_PASSWORD", "MYSQL_PASSWORD", "FLEET_SERVER_PRIVATE_KEY"] {
            #expect(document.fields.first { $0.key == secret }?.kind == "password")
        }
    }

    @Test("The web affordance points at Fleet's port")
    func webPort() throws {
        let document = try importedDocument()
        #expect(document.web?.serviceKey == "fleet")
        // The published port is ${FLEET_SERVER_PORT} on both sides, so the field it
        // already generated is reused rather than a second one being invented.
        #expect(document.web?.portField == "FLEET_SERVER_PORT")
    }

    @Test("The one-shot init container keeps its command")
    func initServiceCommand() throws {
        let command = try service(importedDocument(), "fleet-init").command
        #expect(command?.contains("chown") == true)
    }

    @Test("Named volumes carry through")
    func volumes() throws {
        let document = try importedDocument()
        #expect(try service(document, "mysql").volumes == ["mysql:/var/lib/mysql"])
        let fleetVolumes = try service(document, "fleet").volumes ?? []
        #expect(fleetVolumes.contains("data:/fleet"))
        #expect(fleetVolumes.contains("logs:/logs"))
    }

    /// What the walkthrough has to warn people about, so the warning stays true.
    @Test("What can't be carried over is reported, not dropped silently")
    func caveatsReported() throws {
        let notes = try #require(importedDocument().notes)
        #expect(ComposeImporter.hasLosses(notes))
        for dropped in ["restart", "healthcheck", "cap_add"] {
            #expect(notes.contains(dropped), "\(dropped) not reported")
        }
    }

    /// The certificate bind mounts are unconditional in Fleet's compose file, and the
    /// validator refuses a stack whose host paths don't exist — so the guide's openssl
    /// step is mandatory even when TLS is off. Pinned because it's the first thing a
    /// reader hits.
    @Test("Certificate bind mounts resolve to absolute host paths")
    func certificateMountsAreHostPaths() throws {
        let fleetVolumes = try service(importedDocument(), "fleet").volumes ?? []
        let certMounts = fleetVolumes.filter { $0.contains("fleet.crt") || $0.contains("fleet.key") }
        #expect(certMounts.count == 2)
        for mount in certMounts {
            #expect(mount.hasPrefix("/"), "relative host path was not resolved: \(mount)")
            #expect(mount.hasSuffix(":ro"))
        }
    }
}
