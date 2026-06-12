//
//  RootView.swift
//  ContainerManager
//

import SwiftUI

struct RootView: View {
    @Environment(SystemStore.self) private var systemStore
    @State private var section: SidebarSection = .machines
    @State private var selectedMachineId: String?
    @State private var selectedContainerId: String?
    @State private var selectedImageReference: String?

    var body: some View {
        @Bindable var systemStore = systemStore
        NavigationSplitView {
            SidebarView(selection: $section)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            Group {
                if systemStore.isRunning {
                    switch section {
                    case .machines:
                        MachinesListView(selection: $selectedMachineId)
                    case .containers:
                        ContainersListView(selection: $selectedContainerId)
                    case .images:
                        ImagesListView(selection: $selectedImageReference)
                    }
                } else {
                    DaemonGateView()
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if systemStore.isRunning {
                switch section {
                case .machines:
                    MachineDetailView(machineId: selectedMachineId)
                case .containers:
                    ContainerDetailView(containerId: selectedContainerId)
                case .images:
                    ImageDetailView(reference: selectedImageReference)
                }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .errorAlert($systemStore.lastError)
        .task {
            while !Task.isCancelled {
                await systemStore.refresh()
                let interval: Duration = systemStore.isRunning ? .seconds(15) : .seconds(5)
                try? await Task.sleep(for: interval)
            }
        }
    }
}
