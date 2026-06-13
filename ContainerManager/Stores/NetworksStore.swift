//
//  NetworksStore.swift
//  ContainerManager
//

import ContainerAPIClient
import ContainerResource
import ContainerizationError
import ContainerizationExtras
import Foundation
import Observation

@Observable
final class NetworksStore {
    private(set) var networks: [NetworkResource] = []
    private(set) var busyIds: Set<String> = []
    var lastError: PresentedError?

    func network(withId id: String) -> NetworkResource? {
        networks.first { $0.id == id }
    }

    func isBusy(_ id: String) -> Bool {
        busyIds.contains(id)
    }

    /// Network names sorted for selection, with the built-in default first.
    var selectableNames: [String] {
        networks
            .sorted { ($0.isBuiltin ? 0 : 1, $0.name) < ($1.isBuiltin ? 0 : 1, $1.name) }
            .map(\.name)
    }

    func refresh() async {
        do {
            networks = try await NetworkClient().list().sorted {
                ($0.isBuiltin ? 0 : 1, $0.name) < ($1.isBuiltin ? 0 : 1, $1.name)
            }
        } catch {
            lastError = PresentedError(title: "Failed to load networks", error: error)
        }
    }

    /// Creates a network. `subnet` is an optional CIDR string (e.g. "192.168.65.0/24");
    /// when empty the plugin auto-assigns one. Throws so the sheet can show errors inline.
    func create(name: String, mode: NetworkMode, subnet: String) async throws {
        let ipv4Subnet = try subnet.isEmpty ? nil : CIDRv4(subnet)
        let config = try NetworkConfiguration(
            name: name,
            mode: mode,
            ipv4Subnet: ipv4Subnet,
            plugin: "container-network-vmnet"
        )
        _ = try await NetworkClient().create(configuration: config)
        await refresh()
    }

    func delete(id: String) async {
        busyIds.insert(id)
        defer { busyIds.remove(id) }
        do {
            try await NetworkClient().delete(id: id)
        } catch {
            lastError = PresentedError(title: "Failed to delete network", error: error)
        }
        await refresh()
    }
}
