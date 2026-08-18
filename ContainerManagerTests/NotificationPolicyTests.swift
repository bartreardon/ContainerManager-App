//
//  NotificationPolicyTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// Every rule here fails quietly. A notification that should have fired and didn't is
/// indistinguishable from nothing having happened, and one that fires repeatedly is only
/// ever noticed as irritation — neither leaves a trace to debug.
@Suite("NotificationPolicy")
struct NotificationPolicyTests {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    // MARK: Baseline

    @Test("The first pass reports nothing")
    func firstPassIsBaseline() {
        var policy = NotificationPolicy()
        // Everything already stopped when the app launched is history, not news.
        let outcome1 = policy.stopped(kind: .container, running: ["a", "b"], busy: [])
        #expect(outcome1 == [])
    }

    @Test("A container that disappears from running is reported")
    func stopIsReported() {
        var policy = NotificationPolicy()
        _ = policy.stopped(kind: .container, running: ["a", "b"], busy: [])
        let outcome2 = policy.stopped(kind: .container, running: ["a"], busy: [])
        #expect(outcome2 == ["b"])
    }

    @Test("Something the app is busy with is not reported")
    func selfCausedIsSuppressed() {
        var policy = NotificationPolicy()
        _ = policy.stopped(kind: .container, running: ["a", "b"], busy: [])
        // You clicked Stop, so the store is mid-action on it — you already know.
        let outcome3 = policy.stopped(kind: .container, running: ["a"], busy: ["b"])
        #expect(outcome3 == [])
    }

    @Test("Containers and machines are tracked separately")
    func kindsDoNotCollide() {
        var policy = NotificationPolicy()
        _ = policy.stopped(kind: .container, running: ["shared"], busy: [])
        // A machine of the same name appearing shouldn't read as a container stopping.
        let outcome4 = policy.stopped(kind: .machine, running: [], busy: [])
        #expect(outcome4 == [])
        let outcome5 = policy.stopped(kind: .container, running: [], busy: [])
        #expect(outcome5 == ["shared"])
    }

    @Test("Re-baselining forgets what was running")
    func rebaselineForgets() {
        var policy = NotificationPolicy()
        _ = policy.stopped(kind: .container, running: ["a"], busy: [])
        policy.rebaseline()
        // Switching notifications back on shouldn't announce everything that happened
        // while they were off.
        let outcome6 = policy.stopped(kind: .container, running: [], busy: [])
        #expect(outcome6 == [])
    }

    // MARK: Cooldown

    @Test("The same subject isn't reported twice inside the cooldown")
    func cooldownHolds() {
        var policy = NotificationPolicy()
        let outcome7 = policy.allow("x", now: now)
        #expect(outcome7)
        let outcome8 = policy.allow("x", now: now.addingTimeInterval(60))
        #expect(outcome8 == false)
        let outcome9 = policy.allow("x", now: now.addingTimeInterval(301))
        #expect(outcome9)
    }

    @Test("Different subjects don't share a cooldown")
    func cooldownIsPerSubject() {
        var policy = NotificationPolicy()
        let outcome10 = policy.allow("x", now: now)
        #expect(outcome10)
        let outcome11 = policy.allow("y", now: now)
        #expect(outcome11)
    }

    // MARK: Thresholds

    @Test("A threshold needs several consecutive readings")
    func thresholdNeedsPersistence() {
        var policy = NotificationPolicy()
        // A single spike as something starts up isn't news.
        let outcome12 = policy.crossed("cpu.a", value: 150, limit: 100, now: now)
        #expect(outcome12 == false)
        let outcome13 = policy.crossed("cpu.a", value: 150, limit: 100, now: now)
        #expect(outcome13 == false)
        let outcome14 = policy.crossed("cpu.a", value: 150, limit: 100, now: now)
        #expect(outcome14)
    }

    @Test("Sitting above the threshold reports once, not forever")
    func thresholdDoesNotRepeat() {
        var policy = NotificationPolicy()
        for _ in 0..<3 { _ = policy.crossed("cpu.a", value: 150, limit: 100, now: now) }
        for step in 1...10 {
            let later = now.addingTimeInterval(Double(step))
            let outcome15 = policy.crossed("cpu.a", value: 150, limit: 100, now: later)
            #expect(outcome15 == false)
        }
    }

    @Test("Hovering at the limit doesn't re-fire once recovered slightly")
    func hysteresis() {
        var policy = NotificationPolicy()
        for _ in 0..<3 { _ = policy.crossed("cpu.a", value: 100, limit: 100, now: now) }
        let later = now.addingTimeInterval(400)  // past the cooldown

        // 95 is below the limit but inside the release band, so it isn't "recovered" —
        // it must not re-arm and fire again on the next tick over.
        let outcome16 = policy.crossed("cpu.a", value: 95, limit: 100, now: later)
        #expect(outcome16 == false)
        let outcome17 = policy.crossed("cpu.a", value: 101, limit: 100, now: later)
        #expect(outcome17 == false)
    }

    @Test("A genuine recovery lets it report again")
    func recoveryRearms() {
        var policy = NotificationPolicy()
        for _ in 0..<3 { _ = policy.crossed("cpu.a", value: 150, limit: 100, now: now) }
        let later = now.addingTimeInterval(400)

        _ = policy.crossed("cpu.a", value: 10, limit: 100, now: later)  // well clear
        let outcome18 = policy.crossed("cpu.a", value: 150, limit: 100, now: later)
        #expect(outcome18 == false)
        let outcome19 = policy.crossed("cpu.a", value: 150, limit: 100, now: later)
        #expect(outcome19 == false)
        let outcome20 = policy.crossed("cpu.a", value: 150, limit: 100, now: later)
        #expect(outcome20)
    }

    @Test("A limit of zero means off, not 'everything is over'")
    func zeroLimitIsOff() {
        var policy = NotificationPolicy()
        for _ in 0..<5 {
            let outcome21 = policy.crossed("cpu.a", value: 500, limit: 0, now: now)
            #expect(outcome21 == false)
        }
    }

    // MARK: Coalescing

    @Test("Services of one stack collapse into a single event")
    func stackCoalescing() {
        let stackOf: (String) -> String? = { id in
            id.hasPrefix("fleet-") ? "fleetlab" : nil
        }
        let (stacks, loose) = coalescedByStack(
            ["fleet-mysql", "fleet-redis", "fleet-web", "standalone"], stackOf: stackOf)
        // Eight services going down is one notification about the stack, not eight.
        #expect(stacks == ["fleetlab": 3])
        #expect(loose == ["standalone"])
    }

    @Test("With no stacks involved, everything stays individual")
    func noStacksMeansNoCoalescing() {
        let (stacks, loose) = coalescedByStack(["a", "b"], stackOf: { _ in nil })
        #expect(stacks.isEmpty)
        #expect(loose == ["a", "b"])
    }
}
