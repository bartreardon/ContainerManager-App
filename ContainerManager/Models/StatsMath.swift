//
//  StatsMath.swift
//  ContainerManager
//

import Foundation

/// One raw sample's counters.
///
/// A plain mirror of `ContainerResource.ContainerStats`, lifted out at the store boundary
/// so everything below here is app code. The test target links no package products, and
/// this arithmetic is the part most worth testing.
///
/// Every counter is optional because every one of theirs is: the runtime reports whatever
/// the guest's cgroups gave it, and a missing counter has to stay distinguishable from a
/// zero one.
struct StatsSample: Sendable, Equatable {
    var cpuUsageUsec: UInt64?
    var memoryUsageBytes: UInt64?
    var memoryLimitBytes: UInt64?
    var networkRxBytes: UInt64?
    var networkTxBytes: UInt64?
    var blockReadBytes: UInt64?
    var blockWriteBytes: UInt64?
    var numProcesses: UInt64?
}

/// One derived, display-ready sample for a container.
///
/// Everything except memory and process count is a *rate*, worked out from the difference
/// between two raw samples — the daemon only reports cumulative counters.
struct StatsReading: Identifiable, Sendable {
    let time: Date
    /// 100% is one fully-used core, so a 4-CPU container can reach 400%. Reported raw,
    /// as `container stats` and Activity Monitor do.
    let cpuPercent: Double?
    let memoryUsed: UInt64?
    let memoryLimit: UInt64?
    let networkRxRate: Double?
    let networkTxRate: Double?
    let blockReadRate: Double?
    let blockWriteRate: Double?
    let processes: UInt64?

    var id: Date { time }

    /// Memory used as a plottable value — `values(_:)` graphs `Double`, and every other
    /// metric already is one.
    ///
    /// Spelled out rather than `map(Double.init)`: that resolves to
    /// `Double(bitPattern:)`, which silently reinterprets the byte count as a denormal
    /// around 1e-315 instead of converting it. It type-checks, and the graph just draws
    /// a flat line on the floor.
    var memoryUsedValue: Double? {
        memoryUsed.map { Double($0) }
    }

    /// Memory as a fraction of the limit. Nil unless both are known.
    var memoryFraction: Double? {
        guard let memoryUsed, let memoryLimit, memoryLimit > 0 else { return nil }
        return min(Double(memoryUsed) / Double(memoryLimit), 1)
    }
}

/// A rolling window of readings for one container, plus the raw sample each new one is
/// differenced against.
struct StatsSeries: Sendable {
    /// ~4 minutes at the default 2s interval. Capped because a window is held for every
    /// observed container for as long as something is watching.
    static let capacity = 120

    private(set) var readings: [StatsReading] = []
    /// The last raw sample and when it was taken.
    private var previous: (sample: StatsSample, time: Date)?

    var latest: StatsReading? { readings.last }

    /// True once there's something to draw. A series that has seen only one sample shows
    /// "—" rather than a misleading zero.
    var hasReadings: Bool { !readings.isEmpty }

    /// Adds a raw sample, deriving a reading from it and the one before.
    ///
    /// The first sample of a series produces nothing: a rate needs two, and inventing one
    /// from a single sample would mean inventing the interval too.
    mutating func append(_ sample: StatsSample, at time: Date) {
        let earlier = previous
        previous = (sample, time)
        guard let earlier else { return }
        let interval = Duration.seconds(time.timeIntervalSince(earlier.time))
        guard
            let reading = StatsMath.reading(
                from: earlier.sample, to: sample, over: interval, at: time)
        else { return }
        readings.append(reading)
        if readings.count > Self.capacity {
            readings.removeFirst(readings.count - Self.capacity)
        }
    }

    /// The values one metric took across the window, for a sparkline.
    ///
    /// Gaps are dropped rather than zero-filled, so a run of missing counters shortens
    /// the line instead of drawing a cliff to the floor that would read as "it stopped".
    func values(_ metric: (StatsReading) -> Double?) -> [Double] {
        readings.compactMap(metric)
    }
}

/// Several containers' latest readings added together — what a whole stack is using.
///
/// A field is nil only when *no* contributing container reported it; otherwise it's the
/// sum of the ones that did. A partial total beats no total: one service missing a
/// counter shouldn't blank out the figure for the other four.
struct StatsTotals: Sendable {
    let cpuPercent: Double?
    let memoryUsed: UInt64?
    let memoryLimit: UInt64?
    let networkRxRate: Double?
    let networkTxRate: Double?
    let blockReadRate: Double?
    let blockWriteRate: Double?
    let processes: UInt64?
    /// How many containers contributed a reading, for "3 of 4 services" captions.
    let count: Int

    nonisolated init(_ readings: [StatsReading]) {
        count = readings.count
        cpuPercent = StatsMath.sum(readings.map(\.cpuPercent))
        memoryUsed = StatsMath.sum(readings.map(\.memoryUsed))
        memoryLimit = StatsMath.sum(readings.map(\.memoryLimit))
        networkRxRate = StatsMath.sum(readings.map(\.networkRxRate))
        networkTxRate = StatsMath.sum(readings.map(\.networkTxRate))
        blockReadRate = StatsMath.sum(readings.map(\.blockReadRate))
        blockWriteRate = StatsMath.sum(readings.map(\.blockWriteRate))
        processes = StatsMath.sum(readings.map(\.processes))
    }

    var memoryFraction: Double? {
        guard let memoryUsed, let memoryLimit, memoryLimit > 0 else { return nil }
        return min(Double(memoryUsed) / Double(memoryLimit), 1)
    }
}

/// The arithmetic behind the readings, kept pure and off the main actor so it can be
/// tested without a running daemon.
enum StatsMath {
    /// Adds up the values that are present, or nil when none are.
    nonisolated static func sum<T: AdditiveArithmetic>(_ values: [T?]) -> T? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(.zero, +)
    }

    /// Full scale for a CPU graph: the window's peak rounded up to the next 1, 2 or 5.
    ///
    /// A fixed ceiling of cores × 100 was the honest choice and a useless one — nearly
    /// every container idles under 1%, so the line sat on the floor and the graph showed
    /// nothing. Rounding to 1/2/5 keeps the scale from jittering on every sample the way
    /// a bare `peak` would, and the caption states it so a changing scale stays visible.
    ///
    /// Floored at 5% so a genuinely idle container doesn't magnify its own noise into a
    /// mountain range, and capped at the cores it was given.
    nonisolated static func cpuScale(peak: Double, cores: Int) -> Double {
        let ceiling = Double(max(cores, 1)) * 100
        guard peak > 0, peak.isFinite else { return min(5, ceiling) }
        let magnitude = pow(10, (log10(peak)).rounded(.down))
        let normalized = peak / magnitude
        let step: Double =
            switch normalized {
            case ...1: 1
            case ...2: 2
            case ...5: 5
            default: 10
            }
        return min(max(step * magnitude, 5), ceiling)
    }

    /// Bytes per second between two cumulative counter readings.
    ///
    /// Nil when either sample lacks the counter. Zero when the counter went *backwards*:
    /// a restarted container resets its counters, and the alternative is one enormous
    /// negative spike that rescales the whole graph. `container stats` has the same
    /// guard on its CPU delta.
    nonisolated static func rate(
        from earlier: UInt64?, to later: UInt64?, over interval: Duration
    ) -> Double? {
        guard let earlier, let later else { return nil }
        let seconds = interval / .seconds(1)
        guard seconds > 0 else { return nil }
        guard later > earlier else { return 0 }
        return Double(later - earlier) / seconds
    }

    /// CPU percent from two cumulative microsecond readings, where 100% is one fully-used
    /// core. Same formula as `container stats`, including the backwards-counter clamp.
    nonisolated static func cpuPercent(
        from earlier: UInt64?, to later: UInt64?, over interval: Duration
    ) -> Double? {
        guard let earlier, let later else { return nil }
        guard interval > .zero else { return nil }
        let delta: Duration = later > earlier ? .microseconds(later - earlier) : .zero
        return (delta / interval) * 100
    }

    /// Derives a display-ready reading from two consecutive raw samples.
    ///
    /// Nil when the interval isn't positive — two samples from the same instant say
    /// nothing about a rate, and dividing by that gap would say something false.
    nonisolated static func reading(
        from earlier: StatsSample, to later: StatsSample, over interval: Duration, at time: Date
    ) -> StatsReading? {
        guard interval > .zero else { return nil }
        return StatsReading(
            time: time,
            cpuPercent: cpuPercent(
                from: earlier.cpuUsageUsec, to: later.cpuUsageUsec, over: interval),
            memoryUsed: later.memoryUsageBytes,
            memoryLimit: later.memoryLimitBytes,
            networkRxRate: rate(
                from: earlier.networkRxBytes, to: later.networkRxBytes, over: interval),
            networkTxRate: rate(
                from: earlier.networkTxBytes, to: later.networkTxBytes, over: interval),
            blockReadRate: rate(
                from: earlier.blockReadBytes, to: later.blockReadBytes, over: interval),
            blockWriteRate: rate(
                from: earlier.blockWriteBytes, to: later.blockWriteBytes, over: interval),
            processes: later.numProcesses
        )
    }
}
