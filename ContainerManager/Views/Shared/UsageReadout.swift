//
//  UsageReadout.swift
//  ContainerManager
//

import SwiftUI

/// Shown in place of the numbers when sampling is switched off in Settings.
///
/// An empty graph would read as "this container is doing nothing", which is a different
/// and wrong claim, so the pane says which it is and offers the switch.
struct SamplingOffNotice: View {
    @AppStorage(AppDefaults.statsRefreshKey) private var statsSeconds = 2

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "pause.circle")
                .foregroundStyle(.secondary)
            Text("Sampling is off.")
                .foregroundStyle(.secondary)
            Spacer()
            Button("Turn On") { statsSeconds = 2 }
                .controlSize(.small)
        }
    }
}

/// Shown while a series has fewer than two samples.
///
/// Rates are differences between consecutive samples, so the first one produces no
/// reading at all — there is genuinely nothing to show for one interval.
struct MeasuringNotice: View {
    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Measuring…")
                .foregroundStyle(.secondary)
        }
    }
}

/// Shown when a container has stopped answering its stats requests.
struct NotRespondingNotice: View {
    var body: some View {
        Label(
            "Not responding — the last reading is stale.",
            systemImage: "exclamationmark.triangle.fill"
        )
        .foregroundStyle(.orange)
        .font(.caption)
    }
}

/// A metric's name and current value above its history graph, with the y axis labelled
/// down the left — the shape both panes use for CPU and memory.
///
/// The axis matters because the CPU scale moves: a container that jumps from 1% to 50%
/// gets a taller axis rather than a line off the top, and without the number on screen
/// the graph would look identical before and after.
struct UsageGraphRow: View {
    let title: String
    let value: String
    let series: [UsageGraph.Series]
    /// Top of the y axis, and the graph's full scale.
    let scale: Double
    /// The scale, formatted for its unit — "5.0%", "1.07 GB".
    let scaleLabel: String
    /// Optional note under the graph, for anything the axis doesn't say.
    var caption: String? = nil

    private static let gutterWidth: CGFloat = 54
    private static let graphHeight: CGFloat = 68

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                Spacer()
                Text(value)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 6) {
                axis
                UsageGraph(series: series, fullScale: scale, height: Self.graphHeight)
            }
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(value), full scale \(scaleLabel)")
    }

    /// Top and bottom of the range only. Intermediate labels would need more room than
    /// a form row has, and the gridlines already divide it evenly.
    private var axis: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(scaleLabel)
            Spacer(minLength: 0)
            Text("0")
        }
        .font(.caption2)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: Self.gutterWidth, height: Self.graphHeight, alignment: .trailing)
    }
}

/// The Usage rows for one container: CPU and memory graphs, then throughput and process
/// count as figures.
///
/// Shared because a machine is a container underneath — `MachineSnapshot.containerId` is
/// the id the stats route answers for — so the machine pane shows exactly these rows
/// against exactly this data rather than a second copy that drifts.
struct UsageRows: View {
    /// The container to read; for a machine, its backing container id.
    let containerId: String
    let cores: Int
    /// Used when the runtime doesn't report a memory limit, which it's entitled not to.
    var configuredMemory: UInt64? = nil

    @Environment(StatsStore.self) private var statsStore
    @AppStorage(AppDefaults.statsRefreshKey) private var statsSeconds = 2

    var body: some View {
        // Read through `@AppStorage` rather than `AppDefaults` so switching sampling on
        // in Settings redraws the pane; the sampling loop reads `AppDefaults` live.
        if statsSeconds <= 0 {
            SamplingOffNotice()
        } else if let series = statsStore.series(for: containerId), let latest = series.latest {
            rows(series, latest)
        } else if statsStore.isNotResponding(containerId) {
            NotRespondingNotice()
        } else {
            MeasuringNotice()
        }
    }

    /// Every value is optional all the way down — the runtime reports whatever the guest's
    /// cgroups gave it — so each row falls back to "—" on its own rather than the whole
    /// section disappearing because one counter is missing.
    @ViewBuilder
    private func rows(_ series: StatsSeries, _ latest: StatsReading) -> some View {
        let cpu = series.values(\.cpuPercent)
        let cpuScale = StatsMath.cpuScale(peak: cpu.max() ?? 0, cores: cores)
        UsageGraphRow(
            title: "CPU",
            value: Format.percent(latest.cpuPercent),
            series: [.init(id: "cpu", values: cpu, tint: .accentColor)],
            scale: cpuScale,
            scaleLabel: Format.percent(cpuScale),
            caption: "\(cores) cores — 100% is one fully-used core"
        )
        let memory = series.values(\.memoryUsedValue)
        let memoryScale = memoryScale(latest, peak: memory.max() ?? 0)
        UsageGraphRow(
            title: "Memory",
            value: memoryLabel(latest),
            series: [.init(id: "memory", values: memory, tint: .accentColor)],
            scale: memoryScale,
            scaleLabel: Format.bytes(UInt64(memoryScale))
        )
        LabeledContent("Network") {
            RatePair(inbound: latest.networkRxRate, outbound: latest.networkTxRate)
        }
        LabeledContent("Disk") {
            RatePair(inbound: latest.blockReadRate, outbound: latest.blockWriteRate)
        }
        LabeledContent("Processes", value: Format.count(latest.processes))
        if statsStore.isNotResponding(containerId) {
            NotRespondingNotice()
        }
    }

    /// The limit if anything knows one, and the observed peak otherwise — a graph needs a
    /// ceiling even when nobody will say what it is.
    private func memoryScale(_ latest: StatsReading, peak: Double) -> Double {
        if let limit = latest.memoryLimit ?? configuredMemory, limit > 0 { return Double(limit) }
        return max(peak, 1)
    }

    private func memoryLabel(_ latest: StatsReading) -> String {
        let used = latest.memoryUsed.map(Format.bytes) ?? "—"
        guard let limit = latest.memoryLimit ?? configuredMemory else { return used }
        return "\(used) / \(Format.bytes(limit))"
    }
}

/// Which colour belongs to which service, under a stack's multi-line graph.
struct UsageLegend: View {
    let entries: [(name: String, tint: Color)]

    var body: some View {
        // Wraps rather than truncating: a stack with six services shouldn't lose the
        // last three names to the edge of the pane.
        ViewThatFits(in: .horizontal) {
            row
            VStack(alignment: .leading, spacing: 2) { stacked }
        }
    }

    private var row: some View {
        HStack(spacing: 10) { stacked }
    }

    @ViewBuilder
    private var stacked: some View {
        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
            HStack(spacing: 4) {
                Circle()
                    .fill(entry.tint)
                    .frame(width: 6, height: 6)
                Text(entry.name)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }
}

/// A rate pair — received/sent, or read/written — on one row.
struct RatePair: View {
    let inbound: Double?
    let outbound: Double?

    var body: some View {
        HStack(spacing: 10) {
            Label(Format.rate(inbound), systemImage: "arrow.down")
            Label(Format.rate(outbound), systemImage: "arrow.up")
        }
        .monospacedDigit()
        .labelStyle(.titleAndIcon)
    }
}

/// The compact CPU/memory pair shown on a stack's service rows, styled to match the IP
/// address already sitting there.
struct CompactUsage: View {
    let reading: StatsReading?

    private var memory: String {
        reading?.memoryUsed.map(Format.bytes) ?? "—"
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(Format.percent(reading?.cpuPercent))
            Text(memory)
        }
        .font(.caption.monospaced())
        .foregroundStyle(.secondary)
        .frame(minWidth: 130, alignment: .trailing)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("CPU \(Format.percent(reading?.cpuPercent)), memory \(memory)")
    }
}
