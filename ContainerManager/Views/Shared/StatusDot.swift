//
//  StatusDot.swift
//  ContainerManager
//

import ContainerResource
import SwiftUI

struct StatusDot: View {
    let status: RuntimeStatus

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .help(status.rawValue.capitalized)
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
