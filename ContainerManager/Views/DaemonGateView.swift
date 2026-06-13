//
//  DaemonGateView.swift
//  ContainerManager
//

import SwiftUI

/// Shown in place of the lists when the container system services aren't ready.
struct DaemonGateView: View {
    @Environment(SystemStore.self) private var systemStore

    var body: some View {
        switch systemStore.status {
        case .notInstalled:
            ContentUnavailableView {
                Label("container Is Not Installed", systemImage: "shippingbox")
            } description: {
                Text("ContainerManager needs Apple's container tool. Download and install the latest release, then start its services.")
            } actions: {
                Button("Download & Install…") {
                    Task { await systemStore.install() }
                }
                .buttonStyle(.borderedProminent)
                Link("View releases on GitHub", destination: ContainerInstaller.releasesPage)
                    .font(.caption)
            }

        case .installing:
            VStack(spacing: 12) {
                ProgressView()
                Text(systemStore.busyMessage ?? "Installing…")
                    .font(.callout)
                    .multilineTextAlignment(.center)
            }
            .padding(24)

        case .outdated(let version):
            ContentUnavailableView {
                Label("container Needs Updating", systemImage: "exclamationmark.triangle")
            } description: {
                Text("container \(version) is installed, but ContainerManager needs \(ContainerVersion.minimumString) or later. Stop it first if it's running, then update.")
            } actions: {
                Button("Download & Install Latest…") {
                    Task { await systemStore.install() }
                }
                .buttonStyle(.borderedProminent)
                Link("View releases on GitHub", destination: ContainerInstaller.releasesPage)
                    .font(.caption)
            }

        case .starting:
            startProgress(
                title: "Starting container services…",
                note: "The first start downloads a Linux kernel and base filesystem, which can take a few minutes."
            )

        case .stopping:
            ProgressView("Stopping container services…")

        case .baseEnvMissing:
            ContentUnavailableView {
                Label("Base Environment Missing", systemImage: "exclamationmark.arrow.triangle.2.circlepath")
            } description: {
                Text("The container services are running, but the Linux kernel and/or base filesystem aren't installed — containers can't be created until they are. This usually means an earlier download was interrupted.")
            } actions: {
                Button("Repair…") {
                    Task { await systemStore.repair() }
                }
                .buttonStyle(.borderedProminent)
            }

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

    private func startProgress(title: String, note: String) -> some View {
        VStack(spacing: 12) {
            ProgressView(title)
            Text(note)
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
    }
}
