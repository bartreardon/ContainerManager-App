//
//  ServiceResourceTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// Stack services can now say how much CPU and memory they need. Getting the memory
/// spelling wrong is the dangerous case: too small and the service doesn't fail, it
/// stops answering — which is how Fleet's hourly vulnerability scan takes a 1 GB
/// container off the air.
@Suite("Service resources")
struct ServiceResourceTests {
    // MARK: Compose memory

    @Test(
        "Compose memory spellings convert to the runtime's",
        arguments: [
            ("2g", "2g"), ("512m", "512m"), ("4G", "4g"),
            ("2gb", "2g"), ("512mb", "512m"),
            ("1073741824", "1024m"),  // a bare number is bytes in compose
        ])
    func memorySpellings(given: String, expected: String) {
        #expect(ComposeImporter.normalizedMemory(given) == expected)
    }

    @Test("An empty or unusable memory value is left unset")
    func emptyMemory() {
        #expect(ComposeImporter.normalizedMemory("") == nil)
        #expect(ComposeImporter.normalizedMemory("   ") == nil)
    }

    @Test("A byte count smaller than a megabyte still asks for at least one")
    func tinyMemory() {
        // Rounding to 0m would be rejected by the runtime rather than treated as default.
        #expect(ComposeImporter.normalizedMemory("1024") == "1m")
    }

    // MARK: Where the limits are read from

    @Test("mem_limit is read")
    func memLimit() {
        #expect(ComposeImporter.memoryLimit(["mem_limit": "2g"]) == "2g")
    }

    @Test("deploy.resources.limits is read when mem_limit isn't there")
    func deployLimits() {
        let service: [String: Any] = [
            "deploy": ["resources": ["limits": ["memory": "4g", "cpus": "2.0"]]]
        ]
        #expect(ComposeImporter.memoryLimit(service) == "4g")
        #expect(ComposeImporter.cpuLimit(service) == 2)
    }

    @Test("mem_limit wins over deploy, being the more specific of the two")
    func memLimitWins() {
        let service: [String: Any] = [
            "mem_limit": "1g",
            "deploy": ["resources": ["limits": ["memory": "4g"]]],
        ]
        #expect(ComposeImporter.memoryLimit(service) == "1g")
    }

    @Test("A service saying nothing about resources gets no limits")
    func noLimits() {
        #expect(ComposeImporter.memoryLimit(["image": "nginx"]) == nil)
        #expect(ComposeImporter.cpuLimit(["image": "nginx"]) == nil)
    }

    @Test("Fractional CPU limits round to whole cores")
    func fractionalCPUs() {
        // The runtime allocates whole cores, so 0.5 has to become something.
        #expect(ComposeImporter.cpuLimit(["cpus": "0.5"]) == 1)
        #expect(ComposeImporter.cpuLimit(["cpus": "2.4"]) == 2)
        #expect(ComposeImporter.cpuLimit(["cpus": "0"]) == nil)
    }

    // MARK: Round trip through the document format

    @Test("Resources survive export and re-import")
    func resourcesRoundTrip() throws {
        let spec = StackSpec(
            name: "demo", networkName: "demo-net",
            services: [
                StackServiceSpec(
                    key: "app", displayName: "App", image: "app:1", env: [], volumes: [],
                    publishPorts: [], command: "", platform: nil, cpus: 4, memory: "4g")
            ],
            webServiceKey: nil, webPort: nil)

        let document = StackTemplateDocument.describing(spec, id: "d", name: "D", summary: "")
        let decoded = try StackTemplateDocument.decode(from: try document.encoded())
        let rebuilt = try decoded.toTemplateDef().build(["name": "demo"])

        let service = try #require(rebuilt.services.first)
        #expect(service.cpus == 4)
        #expect(service.memory == "4g")
    }

    @Test("A service with no resources stays that way through a round trip")
    func absentResourcesRoundTrip() throws {
        let spec = StackSpec(
            name: "demo", networkName: "demo-net",
            services: [
                StackServiceSpec(
                    key: "app", displayName: "App", image: "app:1", env: [], volumes: [],
                    publishPorts: [])
            ],
            webServiceKey: nil, webPort: nil)

        let document = StackTemplateDocument.describing(spec, id: "d", name: "D", summary: "")
        let rebuilt = try document.toTemplateDef().build(["name": "demo"])
        #expect(rebuilt.services.first?.cpus == nil)
        #expect(rebuilt.services.first?.memory == nil)
    }
}
