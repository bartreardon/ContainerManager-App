//
//  ContainerRecreationTests.swift
//  ContainerManagerTests
//

import ContainerAPIClient
import ContainerResource
import Foundation
import Testing

@testable import ContainerManager

/// Re-creating removes the original first, so anything the plan gets wrong is lost for
/// good. The configuration here is shaped on a real container's config.json.
@Suite("ContainerRecreation")
struct ContainerRecreationTests {
    static let configuration = """
        {
          "id": "shop-db",
          "image": {
            "reference": "docker.io/library/mysql:8",
            "descriptor": {
              "digest": "sha256:b3b90af2a6552ae30c266fdb7d5dd55f3afb72404bb78d37fe8a23eb857fd3fb",
              "size": 2605,
              "mediaType": "application/vnd.oci.image.index.v1+json"
            }
          },
          "initProcess": {
            "executable": "docker-entrypoint.sh",
            "arguments": ["mysqld", "--character-set-server=utf8mb4"],
            "environment": ["PATH=/usr/bin", "MYSQL_ROOT_PASSWORD=secret"],
            "workingDirectory": "/",
            "terminal": false,
            "rlimits": [],
            "supplementalGroups": [],
            "user": {"raw": {"userString": "mysql"}}
          },
          "mounts": [
            {"type": {"volume": {"name": "shop-data", "format": "ext4", "cache": {"on": {}}, "sync": {"fsync": {}}}},
             "source": "/Users/x/Library/Application Support/com.apple.container/volumes/shop-data/volume.img",
             "destination": "/var/lib/mysql", "options": []},
            {"type": {"virtiofs": {}}, "source": "/Users/x/seed", "destination": "/docker-entrypoint-initdb.d", "options": ["ro"]},
            {"type": {"tmpfs": {}}, "source": "tmpfs", "destination": "/tmp", "options": ["size=64m"]},
            {"type": {"block": {"format": "ext4", "cache": {"on": {}}, "sync": {"fsync": {}}}},
             "source": "/Users/x/extra.img", "destination": "/extra", "options": []}
          ],
          "publishedPorts": [
            {"hostAddress": "127.0.0.1", "hostPort": 3306, "containerPort": 3306, "proto": "tcp", "count": 1},
            {"hostAddress": "0.0.0.0", "hostPort": 5353, "containerPort": 53, "proto": "udp", "count": 1},
            {"hostAddress": "0.0.0.0", "hostPort": 8000, "containerPort": 9000, "proto": "tcp", "count": 3}
          ],
          "labels": {"com.containermanager.stack": "shop", "app": "db"},
          "networks": [{"network": "shop-net", "options": {"hostname": "shop-db", "mtu": 1280}}],
          "platform": {"os": "linux", "architecture": "amd64"},
          "resources": {"cpus": 2, "memoryInBytes": 1073741824, "cpuOverhead": 1},
          "rosetta": true
        }
        """

    static func container(_ json: String = configuration, status: RuntimeStatus = .running) throws -> ContainerSnapshot {
        let configuration = try JSONDecoder().decode(ContainerConfiguration.self, from: Data(json.utf8))
        return ContainerSnapshot(configuration: configuration, status: status, networks: [])
    }

    @Test("The entrypoint and arguments are kept apart, so the entrypoint isn't repeated")
    func entrypoint() throws {
        let spec = ContainerRecreation.plan(for: try Self.container(), autoRemove: false).spec
        #expect(spec.advanced.entrypoint == "docker-entrypoint.sh")
        #expect(spec.advanced.arguments == ["mysqld", "--character-set-server=utf8mb4"])
        #expect(spec.command.isEmpty)
    }

    @Test("Identity, image, environment and resources carry over")
    func basics() throws {
        let spec = ContainerRecreation.plan(for: try Self.container(), autoRemove: true).spec
        #expect(spec.name == "shop-db")
        #expect(spec.image == "docker.io/library/mysql:8")
        #expect(spec.env == ["PATH=/usr/bin", "MYSQL_ROOT_PASSWORD=secret"])
        #expect(spec.cpus == 2)
        #expect(spec.memory == "1g")
        #expect(spec.platform == "linux/amd64")
        #expect(spec.network == "shop-net")
        #expect(spec.labels == ["app=db", "com.containermanager.stack=shop"])
        #expect(spec.autoRemove)
        #expect(spec.advanced.user == "mysql")
        #expect(spec.advanced.workingDirectory == "/")
        #expect(spec.advanced.rosetta)
        #expect(!spec.advanced.tty)
    }

    @Test("Ports keep their address, protocol and range")
    func ports() throws {
        let spec = ContainerRecreation.plan(for: try Self.container(), autoRemove: false).spec
        #expect(spec.publishPorts == ["127.0.0.1:3306:3306/tcp", "5353:53/udp", "8000-8002:9000-9002/tcp"])
    }

    @Test("Volumes, read-only binds and tmpfs carry over; other mounts are named as lost")
    func mounts() throws {
        let plan = ContainerRecreation.plan(for: try Self.container(), autoRemove: false)
        #expect(plan.spec.volumes == ["shop-data:/var/lib/mysql", "/Users/x/seed:/docker-entrypoint-initdb.d:ro"])
        #expect(plan.spec.advanced.tmpfs == ["/tmp:size=64m"])
        #expect(plan.notCarried == ["the mount at /extra"])
    }

    @Test("Settings the create path can't set are named")
    func notCarried() throws {
        let json = Self.configuration
            .replacingOccurrences(of: "\"rosetta\": true", with: "\"rosetta\": true, \"sysctls\": {\"net.core.somaxconn\": \"1024\"}")
            .replacingOccurrences(of: "\"rlimits\": []", with: "\"rlimits\": [{\"limit\": \"RLIMIT_NOFILE\", \"soft\": 1024, \"hard\": 2048}]")
        let plan = ContainerRecreation.plan(for: try Self.container(json), autoRemove: false)
        #expect(plan.notCarried.contains("kernel parameters (sysctls)"))
        #expect(plan.notCarried.contains("resource limits (ulimits)"))
    }

    @Test("A container with no network attachment goes back on the default network")
    func defaultNetwork() throws {
        let json = Self.configuration.replacingOccurrences(
            of: "[{\"network\": \"shop-net\", \"options\": {\"hostname\": \"shop-db\", \"mtu\": 1280}}]", with: "[]")
        let spec = ContainerRecreation.plan(for: try Self.container(json), autoRemove: false).spec
        #expect(spec.network == NetworkClient.defaultNetworkName)
    }

    @Test("The confirmation says what's kept, what's lost, and whether it restarts")
    func confirmation() throws {
        let running = ContainerRecreation.confirmationMessage(for: try Self.container())
        #expect(running.contains("then started again"))
        #expect(running.contains("Not carried over: the mount at /extra."))
        let stopped = ContainerRecreation.confirmationMessage(for: try Self.container(status: .stopped))
        #expect(!stopped.contains("started again"))
    }

    // MARK: Agent detection

    @Test("The snapshot digest is read from the bundle's initial filesystem path")
    func snapshotDigest() {
        let digest = "a69ff331d77997042afc3c7389969be176dfb657ec9ed46366c0e057ec40a297"
        #expect(
            ContainerAgent.snapshotDigest(
                inSource: "/Users/x/Library/Application Support/com.apple.container/snapshots/\(digest)/snapshot")
                == digest)
        #expect(ContainerAgent.snapshotDigest(inSource: "/Users/x/containers/web/initfs.ext4") == nil)
        #expect(ContainerAgent.snapshotDigest(inSource: "/snapshots/not-a-digest/snapshot") == nil)
        #expect(ContainerAgent.snapshotDigest(inSource: "") == nil)
    }

    @Test("The runtime configuration excerpt decodes from a real file's shape")
    func runtimeConfiguration() throws {
        let json = """
            {"path": "file:///x", "kernel": {}, "options": {"autoRemove": true},
             "initialFilesystem": {"source": "/x/snapshots/abc/snapshot", "options": ["ro"], "destination": "/",
                                   "type": {"block": {"format": "ext4"}}}}
            """
        let excerpt = try JSONDecoder().decode(ContainerAgent.RuntimeConfigurationExcerpt.self, from: Data(json.utf8))
        #expect(excerpt.initialFilesystem.source == "/x/snapshots/abc/snapshot")
        #expect(excerpt.options?.autoRemove == true)
    }

    @Test(
        "Agents before containerization 0.43.0 can't reclaim space",
        arguments: [("0.33.3", true), ("0.40.1", true), ("0.42.0", true), ("0.43.0", false), ("0.45.0", false)])
    func agentThreshold(tag: String, tooOld: Bool) {
        #expect(ContainerAgent.isTooOldToReclaim(tag: tag) == tooOld)
    }

    @Test("A tag that isn't a version is unknown, not outdated")
    func unknownTag() {
        #expect(ContainerAgent.isTooOldToReclaim(tag: "latest") == nil)
    }
}
