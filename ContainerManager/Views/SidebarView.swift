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
                .fill(systemStore.status.tint)
                .frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(systemStore.status.label)
                    .font(.callout)
                if let update = systemStore.availableUpdate {
                    Button("Update to \(update)…") { systemStore.promptUpdate() }
                        .buttonStyle(.link)
                        .font(.caption2)
                } else if let health = systemStore.health {
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
}
