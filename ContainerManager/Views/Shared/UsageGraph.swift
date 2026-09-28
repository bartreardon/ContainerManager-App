//
//  UsageGraph.swift
//  ContainerManager
//

import SwiftUI

/// A live history graph, in the style of Activity Monitor's: gridlines, no axis labels,
/// newest sample pinned to the right edge, filling in from the right as it goes.
///
/// Drawn with `Shape` rather than Swift Charts. Activity Monitor's graphs have no axes,
/// ticks, legend or interaction to earn a chart view its keep, and Charts re-lays-out on
/// every tick — which here is every two seconds, per graph, forever.
struct UsageGraph: View {
    /// One line. A container pane draws a single series; a stack pane draws one per
    /// service, which is the whole reason this takes a list.
    struct Series: Identifiable {
        let id: String
        let values: [Double]
        let tint: Color
    }

    let series: [Series]
    /// Full-scale value. Nil autoscales to the tallest sample on screen, which is right
    /// for an unbounded quantity like a byte rate; pass a value for anything with a known
    /// ceiling so a given height means the same thing from one tick to the next.
    var fullScale: Double? = nil
    /// How many samples wide the graph is. Fixing this is what makes the line *scroll*
    /// rather than stretch: with a floating width, three samples would span the full
    /// width and then appear to compress as more arrived.
    var capacity: Int = StatsSeries.capacity
    var height: CGFloat = 68

    private var high: Double {
        // A given full scale wins outright. Letting the window's peak raise it as well
        // meant one outlier sample — a container's memory spiking as it starts — pinned
        // the scale there for the next four minutes and flattened everything after it
        // onto the floor. Values above full scale clamp to the top instead.
        if let fullScale { return max(fullScale, 1) }
        // Autoscaling: never collapse onto a flat line, so an idle container reads as a
        // line along the bottom rather than a full-height one.
        return max(series.flatMap(\.values).max() ?? 1, 1)
    }

    var body: some View {
        let high = high
        ZStack {
            RoundedRectangle(cornerRadius: 4)
                .fill(.quaternary.opacity(0.6))
            GraphGrid(lines: 4)
                .stroke(.tertiary.opacity(0.5), lineWidth: 0.5)
            ForEach(series) { line in
                // A single series reads better filled; several filled areas would just
                // occlude each other.
                if series.count == 1 {
                    GraphPath(values: line.values, high: high, capacity: capacity, closed: true)
                        .fill(line.tint.opacity(0.18))
                }
                GraphPath(values: line.values, high: high, capacity: capacity, closed: false)
                    .stroke(line.tint, style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
            }
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        // The figure printed beside the graph is the accessible version of this.
        .accessibilityHidden(true)
    }
}

/// Evenly spaced horizontal rules, for reading height off the graph at a glance.
private struct GraphGrid: Shape {
    let lines: Int

    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        guard lines > 1 else { return path }
        for index in 1..<lines {
            let y = rect.minY + rect.height * CGFloat(index) / CGFloat(lines)
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        return path
    }
}

/// One series, plotted right-aligned so the newest sample sits at the trailing edge.
private struct GraphPath: Shape {
    let values: [Double]
    let high: Double
    let capacity: Int
    let closed: Bool

    // `Shape` requires this to be nonisolated, and the target defaults to MainActor.
    nonisolated func path(in rect: CGRect) -> Path {
        var path = Path()
        guard values.count > 1, capacity > 1, high > 0 else { return path }

        let step = rect.width / CGFloat(capacity - 1)
        let newest = values.count - 1
        let points = values.enumerated().map { index, value -> CGPoint in
            let fraction = min(max(value / high, 0), 1)
            return CGPoint(
                x: rect.maxX - CGFloat(newest - index) * step,
                y: rect.maxY - CGFloat(fraction) * rect.height
            )
        }

        path.addLines(points)
        if closed, let first = points.first, let last = points.last {
            path.addLine(to: CGPoint(x: last.x, y: rect.maxY))
            path.addLine(to: CGPoint(x: first.x, y: rect.maxY))
            path.closeSubpath()
        }
        return path
    }
}

extension UsageGraph {
    /// Colours for a stack's service lines, walked in order and wrapped.
    ///
    /// Chosen to stay distinguishable next to each other rather than to be pretty; the
    /// legend carries the names, so these only have to be told apart.
    static let palette: [Color] = [.accentColor, .orange, .green, .purple, .pink, .teal]

    static func tint(at index: Int) -> Color {
        palette[index % palette.count]
    }
}
