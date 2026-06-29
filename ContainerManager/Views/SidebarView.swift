//
//  SidebarView.swift
//  ContainerManager
//

import ContainerAPIClient
import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection
    @Environment(ImageImportModel.self) private var imageImport
    @Environment(WindowRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(SidebarSection.allCases) { section in
                    row(section)
                }
            }
            Divider()
            SystemStatusFooter()
        }
    }

    @ViewBuilder
    private func row(_ section: SidebarSection) -> some View {
        let label = Label(section.rawValue, systemImage: section.systemImage)
            .tag(section)
            .contextMenu {
                Button(section.newItemLabel) { router.requestCreate(section) }
            }
        // The Images row also accepts a dropped Dockerfile to start a build.
        if section == .images {
            label.dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first, let text = ImageImportModel.dockerfile(at: url) else { return false }
                imageImport.pendingDockerfile = text
                selection = .images
                return true
            }
        } else {
            label
        }
    }
}

struct SystemStatusFooter: View {
    @Environment(SystemStore.self) private var systemStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(statusText)
                    .font(.callout)
                if let health = systemStore.health {
                    Text("container \(health.apiServerVersion)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            switch systemStore.status {
            case .running, .baseEnvMissing:
                Button("Stop") {
                    Task { await systemStore.stop() }
                }
                .controlSize(.small)
            case .stopped, .unknown:
                Button("Start") {
                    Task { await systemStore.start() }
                }
                .controlSize(.small)
                .disabled(systemStore.status == .unknown)
            case .starting, .stopping, .installing:
                ProgressView()
                    .controlSize(.small)
            case .notInstalled, .outdated:
                EmptyView()
            }
        }
        .padding(10)
    }

    private var statusColor: Color {
        switch systemStore.status {
        case .running: .green
        case .starting, .stopping, .installing: .orange
        case .outdated, .baseEnvMissing: .yellow
        case .stopped, .notInstalled, .unknown: .secondary.opacity(0.5)
        }
    }

    private var statusText: String {
        switch systemStore.status {
        case .running: "Running"
        case .starting: "Starting…"
        case .stopping: "Stopping…"
        case .installing: "Installing…"
        case .stopped: "Stopped"
        case .notInstalled: "Not installed"
        case .outdated: "Update required"
        case .baseEnvMissing: "Setup incomplete"
        case .unknown: "Checking…"
        }
    }
}
