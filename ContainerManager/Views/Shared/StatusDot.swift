//
//  StatusDot.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

/// A status indicator that conveys state by **shape and colour** (not colour alone),
/// and exposes the status as text to VoiceOver.
struct StatusDot: View {
    let status: RuntimeStatus

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 10))
            .foregroundStyle(color)
            .help(label)
            .accessibilityLabel(label)
    }

    private var label: String { status.rawValue.capitalized }

    private var symbol: String {
        switch status {
        case .running: "circle.fill"
        case .stopping: "circle.dotted"
        case .stopped: "circle"
        case .unknown: "questionmark.circle"
        }
    }

    private var color: Color {
        switch status {
        case .running: .green
        case .stopping: .orange
        case .stopped: .secondary.opacity(0.5)
        case .unknown: .red
        }
    }
}
