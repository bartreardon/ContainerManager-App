//
//  StatsMathTests.swift
//  ContainerManagerTests
//

import Foundation
import Testing

@testable import ContainerManager

/// The daemon only reports cumulative counters, so every rate on screen is a difference
/// this code worked out. A mistake here is invisible — wrong numbers still look like
/// numbers — which is why the arithmetic is pure and tested away from a running daemon.
@Suite("StatsMath")
struct StatsMathTests {
    private func sample(
        cpu: UInt64? = nil,
        memory: UInt64? = nil,
        limit: UInt64? = nil,
        rx: UInt64? = nil,
        tx: UInt64? = nil,
        read: UInt64? = nil,
        write: UInt64? = nil,
        processes: UInt64? = nil
    ) -> StatsSample {
        StatsSample(
            cpuUsageUsec: cpu,
            memoryUsageBytes: memory,
            memoryLimitBytes: limit,
            networkRxBytes: rx,
            networkTxBytes: tx,
            blockReadBytes: read,
            blockWriteBytes: write,
            numProcesses: processes
        )
    }

    // MARK: - Rates

    @Test("A rate is the difference over the interval, in bytes per second")
    func rateOverInterval() throws {
        let rate = try #require(StatsMath.rate(from: 1_000, to: 5_000, over: .seconds(2)))
        #expect(rate == 2_000)
    }

    @Test("A counter that went backwards reads as zero, not as a negative spike")
    func counterResetClampsToZero() throws {
        // Restarting a container resets its counters. Without the clamp this is a huge
        // negative value that rescales every graph drawn from the same window.
        let rate = try #require(StatsMath.rate(from: 900_000, to: 12, over: .seconds(2)))
        #expect(rate == 0)
    }

    @Test("A missing counter yields no rate rather than a zero one")
    func missingCounterYieldsNil() {
        #expect(StatsMath.rate(from: nil, to: 5_000, over: .seconds(2)) == nil)
        #expect(StatsMath.rate(from: 1_000, to: nil, over: .seconds(2)) == nil)
    }

    @Test("A non-positive interval yields no rate")
    func zeroIntervalYieldsNil() {
        #expect(StatsMath.rate(from: 1_000, to: 5_000, over: .zero) == nil)
    }

    // MARK: - CPU

    @Test("100% is one fully-used core")
    func cpuPercentOneCore() throws {
        // Two seconds of wall clock, two seconds of CPU time consumed.
        let percent = try #require(StatsMath.cpuPercent(from: 0, to: 2_000_000, over: .seconds(2)))
        #expect(abs(percent - 100) < 0.001)
    }

    @Test("A container using four cores reads 400%")
    func cpuPercentFourCores() throws {
        let percent = try #require(
            StatsMath.cpuPercent(from: 1_000_000, to: 9_000_000, over: .seconds(2)))
        #expect(abs(percent - 400) < 0.001)
    }

    @Test("A CPU counter that went backwards reads as zero")
    func cpuCounterResetClampsToZero() throws {
        let percent = try #require(StatsMath.cpuPercent(from: 9_000_000, to: 5, over: .seconds(2)))
        #expect(percent == 0)
    }

    @Test("A missing CPU counter yields no percentage")
    func cpuMissingCounterYieldsNil() {
        #expect(StatsMath.cpuPercent(from: nil, to: 2_000_000, over: .seconds(2)) == nil)
    }

    // MARK: - Graph scale

    @Test("An idle container gets a 5% scale, not one magnifying its own noise")
    func cpuScaleFloorsAtFivePercent() {
        #expect(StatsMath.cpuScale(peak: 0, cores: 4) == 5)
        #expect(StatsMath.cpuScale(peak: 0.9, cores: 4) == 5)
    }

    @Test("The scale rounds up to the next 1, 2 or 5 so it doesn't jitter")
    func cpuScaleRoundsToReadableSteps() {
        // Anything from 5.1 through 10 shares a scale, so consecutive samples in that
        // band don't rescale the graph under the reader.
        #expect(StatsMath.cpuScale(peak: 6, cores: 4) == 10)
        #expect(StatsMath.cpuScale(peak: 9.5, cores: 4) == 10)
        #expect(StatsMath.cpuScale(peak: 12, cores: 4) == 20)
        #expect(StatsMath.cpuScale(peak: 45, cores: 4) == 50)
        #expect(StatsMath.cpuScale(peak: 130, cores: 4) == 200)
    }

    @Test("The scale never exceeds the cores the container was given")
    func cpuScaleCapsAtCoreCount() {
        #expect(StatsMath.cpuScale(peak: 390, cores: 4) == 400)
        #expect(StatsMath.cpuScale(peak: 800, cores: 4) == 400)
        #expect(StatsMath.cpuScale(peak: 150, cores: 1) == 100)
    }

    @Test("A nonsense peak doesn't produce a nonsense scale")
    func cpuScaleSurvivesBadInput() {
        #expect(StatsMath.cpuScale(peak: .infinity, cores: 4) == 5)
        #expect(StatsMath.cpuScale(peak: .nan, cores: 4) == 5)
        // A container reporting no cores still needs a usable axis.
        #expect(StatsMath.cpuScale(peak: 50, cores: 0) == 50)
    }

    // MARK: - Series

    @Test("The first sample of a series produces no reading")
    func firstSampleProducesNoReading() {
        var series = StatsSeries()
        series.append(sample(cpu: 1_000_000, memory: 512), at: Date())
        // A rate needs two samples. Showing one would mean inventing an interval.
        #expect(series.hasReadings == false)
        #expect(series.latest == nil)
    }

    @Test("The second sample produces a reading derived from both")
    func secondSampleProducesReading() throws {
        let start = Date()
        var series = StatsSeries()
        series.append(sample(cpu: 1_000_000, memory: 512, rx: 0), at: start)
        series.append(
            sample(cpu: 3_000_000, memory: 1_024, rx: 4_000), at: start.addingTimeInterval(2))

        let latest = try #require(series.latest)
        let cpu = try #require(latest.cpuPercent)
        #expect(abs(cpu - 100) < 0.001)
        // Memory is a level, not a rate: it's the later sample's value as-is.
        #expect(latest.memoryUsed == 1_024)
        #expect(try #require(latest.networkRxRate) == 2_000)
    }

    @Test("Memory plots as its actual byte count, not its bit pattern")
    func memoryPlotsAsItsValue() throws {
        let start = Date()
        var series = StatsSeries()
        series.append(sample(memory: 583_100_000, limit: 1_073_741_824), at: start)
        series.append(
            sample(memory: 583_100_000, limit: 1_073_741_824), at: start.addingTimeInterval(2))

        // `map(Double.init)` resolves to `Double(bitPattern:)` and turns this into a
        // denormal near 1e-315 — which type-checks, draws a flat line on the floor, and
        // is invisible in every other assertion because the label reads `memoryUsed`.
        #expect(try #require(series.latest?.memoryUsedValue) == 583_100_000)
        #expect(series.values(\.memoryUsedValue) == [583_100_000])
    }

    @Test("The window is capped, keeping the most recent readings")
    func windowIsCapped() throws {
        let start = Date()
        var series = StatsSeries()
        for index in 0...(StatsSeries.capacity + 20) {
            series.append(
                sample(cpu: UInt64(index) * 1_000_000), at: start.addingTimeInterval(Double(index)))
        }
        #expect(series.readings.count == StatsSeries.capacity)
        // Each step is a full second of CPU over a second of wall clock.
        let cpu = try #require(series.latest?.cpuPercent)
        #expect(abs(cpu - 100) < 0.001)
    }

    @Test("Two samples in the same instant produce no reading")
    func simultaneousSamplesProduceNoReading() {
        let now = Date()
        var series = StatsSeries()
        series.append(sample(cpu: 1_000_000), at: now)
        series.append(sample(cpu: 2_000_000), at: now)
        #expect(series.hasReadings == false)
    }

    @Test("Sparkline values skip gaps rather than plotting them as zero")
    func valuesSkipMissingCounters() {
        let start = Date()
        var series = StatsSeries()
        series.append(sample(cpu: 0, rx: 0), at: start)
        series.append(sample(cpu: 2_000_000, rx: nil), at: start.addingTimeInterval(2))
        series.append(sample(cpu: 4_000_000, rx: nil), at: start.addingTimeInterval(4))

        #expect(series.values(\.cpuPercent).count == 2)
        // A container whose network counter went missing shouldn't draw a line to the
        // floor, which would read as "traffic stopped".
        #expect(series.values(\.networkRxRate).isEmpty)
    }

    // MARK: - Totals

    @Test("Totals add up the readings that are present")
    func totalsSumPresentValues() throws {
        let now = Date()
        let readings = [
            StatsMath.reading(
                from: sample(cpu: 0, memory: 100, limit: 1_000, rx: 0),
                to: sample(cpu: 2_000_000, memory: 100, limit: 1_000, rx: 2_000),
                over: .seconds(2), at: now),
            StatsMath.reading(
                from: sample(cpu: 0, memory: 250, limit: 1_000, rx: 0),
                to: sample(cpu: 1_000_000, memory: 250, limit: 1_000, rx: 1_000),
                over: .seconds(2), at: now),
        ].compactMap { $0 }

        let totals = StatsTotals(readings)
        #expect(totals.count == 2)
        let cpu = try #require(totals.cpuPercent)
        #expect(abs(cpu - 150) < 0.001)
        #expect(totals.memoryUsed == 350)
        #expect(totals.memoryLimit == 2_000)
        #expect(try #require(totals.networkRxRate) == 1_500)
    }

    @Test("A total is partial rather than absent when one container lacks a counter")
    func totalsTolerateMissingCounters() throws {
        let now = Date()
        let readings = [
            StatsMath.reading(
                from: sample(cpu: 0, memory: 100), to: sample(cpu: 2_000_000, memory: 100),
                over: .seconds(2), at: now),
            StatsMath.reading(
                from: sample(), to: sample(), over: .seconds(2), at: now),
        ].compactMap { $0 }

        let totals = StatsTotals(readings)
        let cpu = try #require(totals.cpuPercent)
        #expect(abs(cpu - 100) < 0.001)
        #expect(totals.memoryUsed == 100)
        // Nothing reported a limit, so there genuinely isn't one to show.
        #expect(totals.memoryLimit == nil)
    }

    @Test("Totals over nothing are empty rather than zero")
    func totalsOfNothingAreNil() {
        let totals = StatsTotals([])
        #expect(totals.count == 0)
        #expect(totals.cpuPercent == nil)
        #expect(totals.memoryUsed == nil)
    }
}
