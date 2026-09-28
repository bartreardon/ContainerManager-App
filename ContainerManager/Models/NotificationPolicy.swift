//
//  NotificationPolicy.swift
//  ContainerManager
//

import Foundation

/// What the watcher decided is worth telling someone about.
nonisolated enum NotificationEvent: Equatable {
    case stopped(kind: WatchedKind, id: String, name: String)
    case notResponding(id: String, name: String)
    case stackIncomplete(stack: String, missing: Int)
    case servicesStopped
    case overThreshold(id: String, name: String, metric: ThresholdMetric, value: Double)
    case lowDisk(freeBytes: UInt64)

    /// Identifies the *subject*, not the occurrence — two notifications about the same
    /// container going quiet are the same thing said twice, and the cooldown keys on this.
    var key: String {
        switch self {
        case .stopped(let kind, let id, _): "stopped.\(kind.rawValue).\(id)"
        case .notResponding(let id, _): "quiet.\(id)"
        case .stackIncomplete(let stack, _): "incomplete.\(stack)"
        case .servicesStopped: "services"
        case .overThreshold(let id, _, let metric, _): "over.\(metric.rawValue).\(id)"
        case .lowDisk: "disk"
        }
    }
}

nonisolated enum WatchedKind: String, Equatable {
    case container, machine
}

nonisolated enum ThresholdMetric: String, Equatable {
    case cpu, memory
}

/// Decides what to say and, more often, what not to.
///
/// Kept pure and off the main actor because every rule here fails silently: a
/// notification that should have fired and didn't looks exactly like nothing having
/// happened, and one that fires too often is only noticed as annoyance. Neither shows up
/// in a crash log, so they're tested instead.
nonisolated struct NotificationPolicy {
    /// How long the same subject stays quiet after being reported.
    var cooldown: TimeInterval = 5 * 60
    /// Consecutive readings above a threshold before it counts. A single spike while a
    /// container starts up isn't news.
    var samplesBeforeThreshold = 3
    /// A threshold has to be crossed *downwards* by this much before it can fire again,
    /// or anything sitting at the limit reports forever.
    var releaseFraction = 0.9

    private var lastFired: [String: Date] = [:]
    private var consecutiveOver: [String: Int] = [:]
    /// Subjects already reported and not yet recovered. Without this, anything sitting
    /// above the limit reports again every time the cooldown lapses — for as long as it
    /// runs, which for a busy container is all day.
    private var reported: Set<String> = []
    private var known: [WatchedKind: Set<String>] = [:]

    init() {}

    // MARK: Running → stopped

    /// Ids that stopped without the app asking them to.
    ///
    /// The first call for a kind only records what's running: everything already stopped
    /// when the app launched is history, not news.
    mutating func stopped(kind: WatchedKind, running: Set<String>, busy: Set<String>) -> [String] {
        defer { known[kind] = running }
        guard let previous = known[kind] else { return [] }
        // Busy means the app is mid-action on it — you clicked Stop, so you know.
        return previous.subtracting(running).subtracting(busy).sorted()
    }

    /// Forgets the baseline, so nothing already in progress is reported when the user
    /// switches notifications on.
    mutating func rebaseline() {
        known.removeAll()
        consecutiveOver.removeAll()
        reported.removeAll()
    }

    // MARK: Thresholds

    /// True when `value` has been over `limit` for long enough, and this subject hasn't
    /// just been reported.
    mutating func crossed(_ key: String, value: Double, limit: Double, now: Date) -> Bool {
        guard limit > 0 else { return false }

        if value < limit * releaseFraction {
            // Back down far enough to count as recovered, so it may report again later.
            consecutiveOver[key] = 0
            reported.remove(key)
            return false
        }
        guard value >= limit else { return false }

        let count = (consecutiveOver[key] ?? 0) + 1
        consecutiveOver[key] = count
        guard count >= samplesBeforeThreshold else { return false }
        // Already said so, and it hasn't recovered since.
        guard !reported.contains(key), allow(key, now: now) else { return false }
        reported.insert(key)
        return true
    }

    // MARK: Cooldown

    /// True when this subject hasn't been reported inside the cooldown.
    mutating func allow(_ key: String, now: Date) -> Bool {
        if let last = lastFired[key], now.timeIntervalSince(last) < cooldown { return false }
        lastFired[key] = now
        return true
    }

    /// Drops a subject's history — a container that's gone shouldn't hold a cooldown, and
    /// one that comes back should be able to report again.
    mutating func forget(_ key: String) {
        lastFired[key] = nil
        consecutiveOver[key] = nil
        reported.remove(key)
    }
}

/// Collapses per-service events into one per stack, so an eight-service stack going down
/// is one notification rather than eight.
nonisolated func coalescedByStack(
    _ ids: [String], stackOf: (String) -> String?
) -> (stacks: [String: Int], loose: [String]) {
    var stacks: [String: Int] = [:]
    var loose: [String] = []
    for id in ids {
        if let stack = stackOf(id) {
            stacks[stack, default: 0] += 1
        } else {
            loose.append(id)
        }
    }
    return (stacks, loose)
}
