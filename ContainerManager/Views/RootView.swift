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
    @State private var selectedNetworkId: String?
    @State private var selectedVolumeName: String?
    @State private var selectedStackName: String?

    var body: some View {
        @Bindable var systemStore = systemStore
        NavigationSplitView {
            SidebarView(selection: $section)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            Group {
                if systemStore.isReady {
                    switch section {
                    case .stacks:
                        StacksListView(selection: $selectedStackName)
                    case .machines:
                        MachinesListView(selection: $selectedMachineId)
                    case .containers:
                        ContainersListView(selection: $selectedContainerId)
                    case .images:
                        ImagesListView(selection: $selectedImageReference)
                    case .networks:
                        NetworksListView(selection: $selectedNetworkId)
                    case .volumes:
                        VolumesListView(selection: $selectedVolumeName)
                    }
                } else {
                    DaemonGateView()
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if systemStore.isReady {
                switch section {
                case .stacks:
                    StackDetailView(stackName: selectedStackName)
                case .machines:
                    MachineDetailView(machineId: selectedMachineId)
                case .containers:
                    ContainerDetailView(containerId: selectedContainerId)
                case .images:
                    ImageDetailView(reference: selectedImageReference)
                case .networks:
                    NetworkDetailView(networkId: selectedNetworkId)
                case .volumes:
                    VolumeDetailView(volumeName: selectedVolumeName)
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
                let interval: Duration = systemStore.isReady ? .seconds(15) : .seconds(5)
                try? await Task.sleep(for: interval)
            }
        }
    }
}
