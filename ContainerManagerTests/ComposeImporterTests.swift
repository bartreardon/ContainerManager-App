//
//  ComposeImporterTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// The compose importer is the app's largest piece of pure logic and the one most
/// exposed to files written by other people. Everything but `document(at:)` is
/// private, so these drive it the way the app does — a real file on disk, which also
/// covers the `.env`-beside-the-compose-file behaviour.
@Suite("ComposeImporter")
struct ComposeImporterTests {
    /// Writes `yaml` (and optionally a `.env`) into a scratch folder and hands over the
    /// compose file's URL, cleaning up afterwards.
    private func withComposeFile<T>(
        _ yaml: String, env: String? = nil, named name: String = "myapp.yml",
        body: (URL) throws -> T
    ) throws -> T {
        let folder = URL.temporaryDirectory.appendingPathComponent("compose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent(name)
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        if let env {
            try env.write(
                to: folder.appendingPathComponent(".env"), atomically: true, encoding: .utf8)
        }
        return try body(url)
    }

    private func importing(_ yaml: String, env: String? = nil, named name: String = "myapp.yml")
        throws -> StackTemplateDocument
    {
        try withComposeFile(yaml, env: env, named: name) { try ComposeImporter.document(at: $0) }
    }

    private func service(_ document: StackTemplateDocument, _ key: String) throws
        -> StackTemplateDocument.Service
    {
        try #require(document.services.first { $0.key == key })
    }

    // MARK: Environment

    @Test("environment as a map and as a list produce the same result")
    func environmentBothForms() throws {
        let asMap = try importing(
            """
            services:
              web:
                image: nginx
                environment:
                  ALPHA: one
                  BETA: 2
            """)
        let asList = try importing(
            """
            services:
              web:
                image: nginx
                environment:
                  - ALPHA=one
                  - BETA=2
            """)
        #expect(try service(asMap, "web").env == ["ALPHA=one", "BETA=2"])
        #expect(try service(asList, "web").env == ["ALPHA=one", "BETA=2"])
    }

    @Test("A reference to another service becomes a runtime IP token")
    func serviceReferencesBecomeTokens() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres:16
              web:
                image: nginx
                environment:
                  - BARE=db
                  - WITH_PORT=db:3306
                  - DSN=postgres://user:pass@db:5432/app
                  - URL=http://db:8080/health
                  - UNRELATED=database
            """)
        // List form keeps the file's order; only the map form is sorted.
        #expect(
            try service(document, "web").env == [
                "BARE=${IP:db}",
                "WITH_PORT=${IP:db}:3306",
                "DSN=postgres://user:pass@${IP:db}:5432/app",
                "URL=http://${IP:db}:8080/health",
                // A name merely *containing* a service name is left alone.
                "UNRELATED=database",
            ])
    }

    // MARK: Compose variables

    @Test("${VAR:-default} becomes a field carrying the default")
    func variablesBecomeFields() throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx:${TAG:-alpine}
                environment:
                  - MODE=${MODE}
            """)
        // The inline default is stripped from the value and kept on the field.
        #expect(try service(document, "web").image == "nginx:${TAG}")
        #expect(try service(document, "web").env == ["MODE=${MODE}"])

        let tag = try #require(document.fields.first { $0.key == "TAG" })
        #expect(tag.default == "alpine")
        let mode = try #require(document.fields.first { $0.key == "MODE" })
        #expect(mode.default == "")
    }

    @Test("Secret-looking variables are entered as passwords")
    func secretsGetPasswordFields() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres
                environment:
                  - POSTGRES_PASSWORD=${DB_PASSWORD}
                  - API_TOKEN=${TOKEN}
                  - REGION=${REGION}
            """)
        #expect(document.fields.first { $0.key == "DB_PASSWORD" }?.kind == "password")
        #expect(document.fields.first { $0.key == "TOKEN" }?.kind == "password")
        #expect(document.fields.first { $0.key == "REGION" }?.kind == nil)
    }

    @Test("A .env beside the compose file prefills the fields")
    func envFilePrefills() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres
                environment:
                  - POSTGRES_PASSWORD=${DB_PASSWORD}
                  - POSTGRES_USER=${DB_USER}
            """,
            env: """
                # a comment
                DB_PASSWORD=hunter2
                """)
        #expect(document.fields.first { $0.key == "DB_PASSWORD" }?.default == "hunter2")
        #expect(document.fields.first { $0.key == "DB_USER" }?.default == "")
        #expect(document.notes?.contains("Prefilled 1 of 2") == true)
    }

    @Test("With no .env, the notes say where to enter the variables")
    func missingEnvFileIsExplained() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres
                environment:
                  - POSTGRES_PASSWORD=${DB_PASSWORD}
            """)
        #expect(document.notes?.contains("Found 1 variables") == true)
        #expect(ComposeImporter.caveats(in: document) != nil)
    }

    // MARK: Ordering

    @Test("depends_on decides start order")
    func dependenciesAreSorted() throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx
                depends_on:
                  - api
              api:
                image: api:1
                depends_on:
                  - db
              db:
                image: postgres
            """)
        #expect(document.services.map(\.key) == ["db", "api", "web"])
    }

    @Test("depends_on in map form is honoured too")
    func dependenciesAsMap() throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx
                depends_on:
                  db:
                    condition: service_healthy
              db:
                image: postgres
            """)
        #expect(document.services.map(\.key) == ["db", "web"])
    }

    @Test("A dependency cycle is rejected rather than half-built")
    func cyclesAreRejected() throws {
        #expect(throws: ComposeImporter.ComposeError.self) {
            try importing(
                """
                services:
                  a:
                    image: a:1
                    depends_on: [b]
                  b:
                    image: b:1
                    depends_on: [a]
                """)
        }
    }

    // MARK: Volumes and ports

    @Test("Volumes in short and long form both convert")
    func volumeForms() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres
                volumes:
                  - data:/var/lib/postgresql/data
                  - type: volume
                    source: config
                    target: /etc/app
                    read_only: true
            """)
        #expect(
            try service(document, "db").volumes == [
                "data:/var/lib/postgresql/data", "config:/etc/app:ro",
            ])
    }

    @Test("An anonymous volume is skipped and reported")
    func anonymousVolumesAreReported() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres
                volumes:
                  - target: /scratch
            """)
        #expect(try service(document, "db").volumes == nil)
        #expect(document.notes?.contains("anonymous volume") == true)
    }

    @Test("A relative host path resolves against the compose file's folder")
    func relativeHostPathsResolve() throws {
        let volumes = try withComposeFile(
            """
            services:
              web:
                image: nginx
                volumes:
                  - ./site:/usr/share/nginx/html
            """
        ) { url -> [String] in
            let document = try ComposeImporter.document(at: url)
            return document.services[0].volumes ?? []
        }
        let entry = try #require(volumes.first)
        #expect(entry.hasPrefix("/"))
        #expect(entry.hasSuffix("/site:/usr/share/nginx/html"))
    }

    @Test("Ports in short and long form both convert")
    func portForms() throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx
                ports:
                  - "8080:80"
                  - target: 443
                    published: 8443
            """)
        #expect(try service(document, "web").publishPorts == ["${port}:80", "8443:443"])
    }

    // MARK: The web affordance

    @Test("The last service's first published port becomes the web port field")
    func webPortIsDetected() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres
                ports:
                  - "5432:5432"
              web:
                image: nginx
                depends_on: [db]
                ports:
                  - "8080:80"
            """)
        #expect(document.web?.serviceKey == "web")
        #expect(document.web?.portField == "port")
        #expect(document.fields.first { $0.key == "port" }?.default == "8080")
        // The mapping is rewritten to reference the new field.
        #expect(try service(document, "web").publishPorts == ["${port}:80"])
        // The other service keeps its literal mapping.
        #expect(try service(document, "db").publishPorts == ["5432:5432"])
    }

    @Test("A container-only port exposes no web affordance")
    func noHostPortNoWeb() throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx
                ports:
                  - "80"
            """)
        #expect(document.web == nil)
    }

    // MARK: Commands and platform

    @Test("command as a string and as a list both survive")
    func commandForms() throws {
        let asString = try importing(
            """
            services:
              web:
                image: nginx
                command: sh -c "echo hi"
            """)
        let asList = try importing(
            """
            services:
              web:
                image: nginx
                command: ["sh", "-c", "echo hi"]
            """)
        #expect(try service(asString, "web").command == #"sh -c "echo hi""#)
        #expect(try service(asList, "web").command == #"sh -c "echo hi""#)
    }

    @Test(
        "platform is normalized to the OCI spelling",
        arguments: [
            ("linux/x86_64", "linux/amd64"), ("linux/amd64", "linux/amd64"),
            ("linux/aarch64", "linux/arm64"), ("linux/arm64", "linux/arm64"),
        ])
    func platformIsNormalized(given: String, expected: String) throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx
                platform: \(given)
            """)
        #expect(try service(document, "web").platform == expected)
    }

    // MARK: Rejections and losses

    @Test("A file that isn't compose is rejected")
    func notCompose() {
        #expect(throws: ComposeImporter.ComposeError.self) { try importing("just a string") }
    }

    @Test("A compose file with no services is rejected")
    func noServices() {
        #expect(throws: ComposeImporter.ComposeError.self) { try importing("version: \"3.9\"") }
    }

    @Test("A service with neither image nor build is rejected")
    func missingImage() {
        #expect(throws: ComposeImporter.ComposeError.self) {
            try importing(
                """
                services:
                  web:
                    ports: ["80:80"]
                """)
        }
    }

    @Test("A build-only service is skipped, and the rest still import")
    func buildServiceIsSkipped() throws {
        let document = try importing(
            """
            services:
              app:
                build: .
              db:
                image: postgres
            """)
        #expect(document.services.map(\.key) == ["db"])
        #expect(document.notes?.contains("app (build:)") == true)
    }

    @Test("When every service uses build:, the import fails with advice")
    func allBuildFails() {
        #expect(throws: ComposeImporter.ComposeError.self) {
            try importing(
                """
                services:
                  app:
                    build: .
                """)
        }
    }

    @Test("Unsupported keys are listed with the reason they were dropped")
    func unsupportedKeysAreReported() throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx
                restart: always
                user: nobody
            """)
        let notes = try #require(document.notes)
        #expect(notes.contains("Not imported:"))
        #expect(notes.contains("web.restart:"))
        #expect(notes.contains("web.user:"))
        #expect(ComposeImporter.hasLosses(notes))
    }

    @Test("Top-level keys that aren't carried over are reported too")
    func topLevelKeysAreReported() throws {
        let document = try importing(
            """
            secrets:
              db_password:
                file: ./secret.txt
            services:
              web:
                image: nginx
            """)
        #expect(document.notes?.contains("secrets:") == true)
    }

    @Test("A clean import reports no losses")
    func cleanImportHasNoLosses() throws {
        let document = try importing(
            """
            services:
              web:
                image: nginx
                ports: ["8080:80"]
            """)
        #expect(ComposeImporter.hasLosses(document.notes ?? "") == false)
        #expect(ComposeImporter.caveats(in: document) == nil)
    }

    // MARK: The whole trip

    @Test("An imported document is a valid template that builds a stack")
    func importedDocumentBuilds() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres:16
                environment:
                  POSTGRES_PASSWORD: ${DB_PASSWORD:-secret}
                volumes:
                  - db-data:/var/lib/postgresql/data
              web:
                image: nginx
                depends_on: [db]
                environment:
                  - DB_HOST=db
                ports:
                  - "8080:80"
            """)

        let spec = try document.toTemplateDef().build([
            "name": "My App", "port": "9090", "DB_PASSWORD": "hunter2",
        ])
        #expect(spec.name == "my-app")
        #expect(spec.services.map(\.key) == ["db", "web"])
        #expect(spec.webServiceKey == "web")
        #expect(spec.webPort == 9090)
        #expect(spec.services[0].env == ["POSTGRES_PASSWORD=hunter2"])
        // The IP token is still a token — the orchestrator resolves it at run time.
        #expect(spec.services[1].env == ["DB_HOST=${IP:db}"])
        #expect(spec.services[1].publishPorts == ["9090:80"])
    }

    /// Containers are named after the stack and service key, so a fixed
    /// `container_name` can't be honoured — but it has to be *reported*, or a compose
    /// file that names its containers imports silently and gets different ones.
    @Test("container_name is reported rather than silently dropped")
    func containerNameIsReported() throws {
        let document = try importing(
            """
            services:
              db:
                image: postgres
                container_name: my-database
            """)
        #expect(document.services.map(\.key) == ["db"])
        let notes = try #require(document.notes)
        #expect(notes.contains("db.container_name:"))
        #expect(notes.contains("named after the stack and the service"))
        #expect(ComposeImporter.hasLosses(notes))
    }
}
