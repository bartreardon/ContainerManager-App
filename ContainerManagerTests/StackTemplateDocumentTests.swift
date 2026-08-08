//
//  StackTemplateDocumentTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// The `.containerstack` format is the app's import/export contract and the record a
/// stack is repaired from, so a substitution mistake either builds the wrong stack or
/// destroys a definition on round-trip.
///
/// `substitute` is private, and deliberately tested through `toTemplateDef()` — the
/// seam the importer and the create sheets actually use.
@Suite("StackTemplateDocument")
struct StackTemplateDocumentTests {
    /// A document with one service, built from the pieces each test needs.
    private func document(
        service: StackTemplateDocument.Service,
        fields: [StackTemplateDocument.Field] = [.init(key: "name", label: "Name", default: "demo")],
        web: StackTemplateDocument.Web? = nil,
        version: Int = StackTemplateDocument.currentVersion
    ) -> StackTemplateDocument {
        StackTemplateDocument(
            version: version, id: "test", name: "Test", summary: "",
            systemImage: nil, notes: nil, fields: fields, services: [service], web: web)
    }

    private func service(
        image: String = "nginx:latest",
        env: [String]? = nil,
        volumes: [String]? = nil,
        publishPorts: [String]? = nil,
        command: String? = nil
    ) -> StackTemplateDocument.Service {
        .init(
            key: "web", displayName: "Web", image: image, env: env, volumes: volumes,
            publishPorts: publishPorts, command: command, platform: nil)
    }

    // MARK: Substitution

    @Test("Field tokens are replaced everywhere a string is accepted")
    func substitutesEveryStringPosition() throws {
        let fields: [StackTemplateDocument.Field] = [
            .init(key: "name", label: "Name", default: "demo"),
            .init(key: "tag", label: "Tag", default: "1.0"),
        ]
        let document = document(
            service: service(
                image: "app:${tag}",
                env: ["VERSION=${tag}"],
                volumes: ["${name}-data:/var/lib/app"],
                publishPorts: ["8080:80"],
                command: "serve --tag ${tag}"),
            fields: fields)

        let spec = try document.toTemplateDef().build(["name": "demo", "tag": "2.1"])
        let web = try #require(spec.services.first)
        #expect(web.image == "app:2.1")
        #expect(web.env == ["VERSION=2.1"])
        #expect(web.volumes == ["demo-data:/var/lib/app"])
        #expect(web.command == "serve --tag 2.1")
    }

    @Test("Runtime IP tokens survive substitution untouched")
    func ipTokensArePreserved() throws {
        let document = document(
            service: service(env: ["DB_HOST=${IP:db}:3306", "MIX=${IP:db}/${name}"]))

        let spec = try document.toTemplateDef().build(["name": "demo"])
        let service = try #require(spec.services.first)
        #expect(service.env == ["DB_HOST=${IP:db}:3306", "MIX=${IP:db}/demo"])
    }

    @Test("A token matching no field is rejected when the document is loaded")
    func unknownPlaceholderIsRejectedAtLoad() {
        // Not at create time — the point is that a bad import is caught before
        // anything is built.
        let document = document(service: service(env: ["KEY=${nope}"]))
        #expect(throws: StackTemplateDocument.DocumentError.self) {
            try document.toTemplateDef()
        }
    }

    @Test("An unterminated token is kept literally rather than throwing")
    func unterminatedTokenIsLiteral() throws {
        let document = document(service: service(env: ["KEY=${name"]))
        let spec = try document.toTemplateDef().build(["name": "demo"])
        #expect(spec.services.first?.env == ["KEY=${name"])
    }

    // MARK: Validation

    @Test("Only format version 1 decodes")
    func versionIsChecked() throws {
        let data = try document(service: service(), version: 2).encoded()
        #expect(throws: StackTemplateDocument.DocumentError.self) {
            try StackTemplateDocument.decode(from: data)
        }
    }

    @Test("A document without a name field is rejected")
    func nameFieldRequired() {
        let document = document(
            service: service(), fields: [.init(key: "tag", label: "Tag", default: "1")])
        #expect(throws: StackTemplateDocument.DocumentError.self) {
            try document.toTemplateDef()
        }
    }

    @Test("web.portField must name a real field")
    func webPortFieldMustExist() {
        let document = document(
            service: service(), web: .init(serviceKey: "web", portField: "missing"))
        #expect(throws: StackTemplateDocument.DocumentError.self) {
            try document.toTemplateDef()
        }
    }

    @Test("A port field rejects values outside 1–65535", arguments: ["0", "65536", "http", ""])
    func portsAreValidated(value: String) throws {
        let document = document(
            service: service(),
            fields: [
                .init(key: "name", label: "Name", default: "demo"),
                .init(key: "port", label: "Port", default: "8080", kind: "port"),
            ],
            web: .init(serviceKey: "web", portField: "port"))
        let template = try document.toTemplateDef()
        // An empty value falls back to the default, which is valid — the others don't.
        if value.isEmpty {
            #expect(try template.build(["name": "demo", "port": value]).webPort == 8080)
        } else {
            #expect(throws: StackTemplateError.self) {
                try template.build(["name": "demo", "port": value])
            }
        }
    }

    @Test("The stack name is sanitized into a usable resource name")
    func nameIsSanitized() throws {
        let spec = try document(service: service()).toTemplateDef()
            .build(["name": "My Stack!"])
        #expect(spec.name == "my-stack")
        #expect(spec.networkName == "my-stack-net")
    }

    @Test("Blank values fall back to the field default")
    func blankFallsBackToDefault() throws {
        let spec = try document(service: service()).toTemplateDef().build(["name": "   "])
        #expect(spec.name == "demo")
    }

    @Test("The web service and port reach the spec")
    func webIsCarriedThrough() throws {
        let document = document(
            service: service(),
            fields: [
                .init(key: "name", label: "Name", default: "demo"),
                .init(key: "port", label: "Port", default: "8080", kind: "port"),
            ],
            web: .init(serviceKey: "web", portField: "port"))
        let spec = try document.toTemplateDef().build(["name": "demo", "port": "9090"])
        #expect(spec.webServiceKey == "web")
        #expect(spec.webPort == 9090)
    }

    // MARK: describing() — the export/repair path

    @Test("A literal ${ in a value is escaped so it can't read as a placeholder")
    func literalDollarBraceIsEscaped() throws {
        let spec = StackSpec(
            name: "demo", networkName: "demo-net",
            services: [
                StackServiceSpec(
                    key: "web", displayName: "Web", image: "nginx",
                    env: ["MESSAGE=cost is ${100}"], volumes: [], publishPorts: [])
            ],
            webServiceKey: nil, webPort: nil)

        let document = StackTemplateDocument.describing(spec, id: "d", name: "D", summary: "")
        #expect(document.services[0].env == ["MESSAGE=cost is $ {100}"])
        // The point of the escaping: it survives being loaded back.
        #expect(throws: Never.self) { try document.toTemplateDef() }
    }

    @Test("Values carrying a runtime IP token are left alone")
    func ipTokensAreNotEscaped() {
        let spec = StackSpec(
            name: "demo", networkName: "demo-net",
            services: [
                StackServiceSpec(
                    key: "app", displayName: "App", image: "app",
                    env: ["DB=${IP:db}:5432"], volumes: [], publishPorts: [])
            ],
            webServiceKey: nil, webPort: nil)

        let document = StackTemplateDocument.describing(spec, id: "d", name: "D", summary: "")
        #expect(document.services[0].env == ["DB=${IP:db}:5432"])
    }

    @Test("A described stack round-trips through encode and decode")
    func describedStackRoundTrips() throws {
        let spec = StackSpec(
            name: "demo", networkName: "demo-net",
            services: [
                StackServiceSpec(
                    key: "app", displayName: "App", image: "app:1", env: ["A=1"],
                    volumes: ["demo-data:/data"], publishPorts: ["8080:80"],
                    command: "serve", platform: "linux/amd64")
            ],
            webServiceKey: "app", webPort: 8080)

        let document = StackTemplateDocument.describing(spec, id: "d", name: "D", summary: "s")
        let decoded = try StackTemplateDocument.decode(from: try document.encoded())
        let rebuilt = try decoded.toTemplateDef().build(["name": "demo", "port": "8080"])

        #expect(rebuilt.name == "demo")
        #expect(rebuilt.webServiceKey == "app")
        #expect(rebuilt.webPort == 8080)
        let service = try #require(rebuilt.services.first)
        #expect(service.image == "app:1")
        #expect(service.env == ["A=1"])
        #expect(service.volumes == ["demo-data:/data"])
        #expect(service.publishPorts == ["8080:80"])
        #expect(service.command == "serve")
        #expect(service.platform == "linux/amd64")
    }
}
