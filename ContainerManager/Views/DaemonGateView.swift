//
//  DaemonGateView.swift
//  ContainerManager
//

import SwiftUI

/// Shown in place of the lists when the container system services aren't available.
struct DaemonGateView: View {
    @Environment(SystemStore.self) private var systemStore

    var body: some View {
        switch systemStore.status {
        case .notInstalled:
            ContentUnavailableView {
                Label("container Is Not Installed", systemImage: "shippingbox")
            } description: {
                Text("Install the container tool from github.com/apple/container, then come back here to start its services.")
            }
        case .starting:
            VStack(spacing: 12) {
                ProgressView("Starting container services…")
                Text("The first start downloads a Linux kernel and base filesystem, which can take a few minutes.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !systemStore.actionOutput.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(systemStore.actionOutput.enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption.monospaced())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                Color.clear.frame(height: 1).id("bottom")
                            }
                            .padding(8)
                        }
                        .frame(maxHeight: 180)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 6))
                        .onChange(of: systemStore.actionOutput.count) {
                            proxy.scrollTo("bottom")
                        }
                    }
                }
            }
            .padding(24)
        case .stopping:
            ProgressView("Stopping container services…")
        case .stopped, .unknown:
            ContentUnavailableView {
                Label("Container Services Are Not Running", systemImage: "power")
            } description: {
                Text("Start the container system service to manage containers and machines.")
            } actions: {
                Button("Start") {
                    Task { await systemStore.start() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(systemStore.status == .unknown)
            }
        case .running:
            EmptyView()
        }
    }
}
