//
//  StatsStore.swift
//  ContainerManager
//

import AppKit
import ContainerAPIClient
import ContainerResource
import Foundation
import Observation

/// Rolling resource usage for the containers you've been looking at.
///
/// Unlike the other stores this one is *demand-driven*: nothing is sampled until a view
/// asks for it, and everything stops when the last window closes. `container` has no bulk
/// stats route, so each container costs one XPC round trip per tick — around 25ms of
/// daemon work, taken under the same per-container lock that start/stop/exec use. Cheap,
/// but not free enough to run over every container on the machine forever.
///
/// Sampling deliberately *outlives* the view that asked for it. Stopping the instant a
/// pane closed meant clicking Containers → Stacks → back left a hole in the graph and
/// restarted the four-minute window from nothing. Containers stay in the rotation until
/// they're pushed out by more recently viewed ones, or the last window goes away.
///
/// This is why `.autoRefresh` isn't reused here: it polls for exactly as long as a view
/// exists, which is the one lifetime that turned out to be wrong.
@Observable
final class StatsStore {
    /// How many containers stay in the rotation. Clicking through a long list shouldn't
    /// leave a poller running for every container it passed.
    static let retentionLimit = 12

    private(set) var series: [String: StatsSeries] = [:]

    /// Which containers each live `observe(_:)` call wants — the ones actually on screen.
    private var observers: [UUID: Set<String>] = [:]
    /// Everything still being sampled, least recently viewed first.
    private var retained: [String] = []
    /// Containers with a request already outstanding. A wedged container never answers
    /// and never leaves this set, which is deliberate: it stops ticks piling up
    /// un-cancellable XPC calls behind it. See `isNotResponding(_:)`.
    private var inFlight: Set<String> = []
    /// When each container's last request was *issued* — not when it came back — so a
    /// slow reply can't trigger a second one.
    private var issued: [String: Date] = [:]
    private var loop: Task<Void, Never>?

    /// One connection for the life of the store. Every other store builds a client per
    /// call, which is fine at one call per action; at one per container every two seconds
    /// it's a mach connection created and activated over and over.
    private let client = ContainerClient()

    func series(for id: String) -> StatsSeries? {
        series[id]
    }

    /// True when a sample has been outstanding far longer than the interval — the
    /// container has stopped answering.
    ///
    /// Worth surfacing rather than hiding behind stale numbers: a container gone quiet
    /// under memory pressure is exactly what sends you looking at stats, and
    /// `ContainerClient.stats` has no timeout and can't be cancelled once sent, so a
    /// frozen reading is the only evidence there is.
    func isNotResponding(_ id: String) -> Bool {
        guard inFlight.contains(id), let issued = issued[id] else { return false }
        let interval = AppDefaults.statsRefresh ?? .seconds(2)
        return Date().timeIntervalSince(issued) > (interval / .seconds(1)) * 3
    }

    /// Keeps `ids` sampled while the caller isn't cancelled — call it from `.task`.
    ///
    /// Returning doesn't stop the sampling; it only gives up the claim that protects
    /// those containers from being evicted. That's what lets a graph survive a trip to
    /// another section and come back continuous.
    func observe(_ ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        let token = UUID()
        observers[token] = ids
        promote(ids)
        startLoop()
        defer { observers[token] = nil }

        // Park until cancelled. There's no work to do here — the store's own loop does
        // the sampling — so this just holds the claim open for the view's lifetime.
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(60))
        }
    }

    /// Moves `ids` to the most-recently-viewed end of the rotation and evicts the oldest
    /// beyond the limit.
    private func promote(_ ids: Set<String>) {
        retained.removeAll { ids.contains($0) }
        retained.append(contentsOf: ids.sorted())

        let onScreen = observers.values.reduce(into: Set<String>()) { $0.formUnion($1) }
        while retained.count > Self.retentionLimit {
            // Never evict something a view is currently showing, however old its claim.
            guard let index = retained.firstIndex(where: { !onScreen.contains($0) }) else { break }
            forget(retained.remove(at: index))
        }
    }

    private func forget(_ id: String) {
        series[id] = nil
        issued[id] = nil
        inFlight.remove(id)
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.isWanted else {
                    self?.stop()
                    return
                }
                guard let interval = AppDefaults.statsRefresh else {
                    // Sampling is off. Idle rather than exit, so turning it back on in
                    // Settings takes effect without reopening a pane.
                    try? await Task.sleep(for: .seconds(2))
                    continue
                }
                self.tick(interval: interval)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Sampling is worth continuing while there's something to sample and a window to
    /// show it in. Menu-bar-only is the app's idle state — measuring through it would be
    /// a background tax nobody asked for.
    private var isWanted: Bool {
        !retained.isEmpty && AppWindows.hasOrdinaryVisible
    }

    private func stop() {
        loop?.cancel()
        loop = nil
        retained.removeAll()
        series.removeAll()
        issued.removeAll()
        inFlight.removeAll()
    }

    /// Issues a sample for every retained container that's due one.
    ///
    /// Nothing here waits on the results: a tick's job is to *start* the requests. One
    /// container that never replies must not hold up the others, and a `TaskGroup` would
    /// do exactly that — it can't return until every child finishes, and these children
    /// aren't cancellable.
    private func tick(interval: Duration) {
        let seconds = interval / .seconds(1)
        let now = Date()
        for id in retained {
            guard !inFlight.contains(id) else { continue }
            // A little slack, so a tick that lands fractionally early doesn't skip a
            // container and halve its effective sample rate.
            if let last = issued[id], now.timeIntervalSince(last) < seconds * 0.9 { continue }
            sample(id: id)
        }
    }

    private func sample(id: String) {
        inFlight.insert(id)
        issued[id] = Date()
        Task { [client] in
            let stats = try? await client.stats(id: id)
            inFlight.remove(id)
            // The container may have been evicted or the store torn down while this was
            // in flight; a late reply shouldn't resurrect it.
            guard retained.contains(id) else { return }
            guard let stats else {
                // A container that stopped mid-tick fails its stats call. That's the
                // expected race, not a fault, so the series goes quietly rather than
                // raising an error the way the other stores would.
                forget(id)
                retained.removeAll { $0 == id }
                return
            }
            series[id, default: StatsSeries()].append(StatsSample(stats), at: Date())
        }
    }
}

extension StatsSample {
    /// Lifts the package's stats type into the app's own, so nothing below the store has
    /// to know about `ContainerResource`.
    init(_ stats: ContainerStats) {
        self.init(
            cpuUsageUsec: stats.cpuUsageUsec,
            memoryUsageBytes: stats.memoryUsageBytes,
            memoryLimitBytes: stats.memoryLimitBytes,
            networkRxBytes: stats.networkRxBytes,
            networkTxBytes: stats.networkTxBytes,
            blockReadBytes: stats.blockReadBytes,
            blockWriteBytes: stats.blockWriteBytes,
            numProcesses: stats.numProcesses
        )
    }
}
