//
//  RootView.swift
//  ContainerManager
//

import SwiftUI

struct RootView: View {
    @Environment(SystemStore.self) private var systemStore
    @State private var router = WindowRouter()

    var body: some View {
        @Bindable var systemStore = systemStore
        @Bindable var router = router
        NavigationSplitView {
            SidebarView(selection: $router.section)
                .navigationSplitViewColumnWidth(min: 180, ideal: 200)
        } content: {
            Group {
                if systemStore.isReady {
                    switch router.section {
                    case .stacks:
                        StacksListView(selection: $router.selectedStackName)
                    case .machines:
                        MachinesListView(selection: $router.selectedMachineId)
                    case .containers:
                        ContainersListView(selection: $router.selectedContainerId)
                    case .images:
                        ImagesListView(selection: $router.selectedImageReference)
                    case .networks:
                        NetworksListView(selection: $router.selectedNetworkId)
                    case .volumes:
                        VolumesListView(selection: $router.selectedVolumeName)
                    }
                } else {
                    DaemonGateView()
                }
            }
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if systemStore.isReady {
                switch router.section {
                case .stacks:
                    StackDetailView(stackName: router.selectedStackName)
                case .machines:
                    MachineDetailView(machineId: router.selectedMachineId)
                case .containers:
                    ContainerDetailView(containerId: router.selectedContainerId)
                case .images:
                    ImageDetailView(reference: router.selectedImageReference)
                case .networks:
                    NetworkDetailView(networkId: router.selectedNetworkId)
                case .volumes:
                    VolumeDetailView(volumeName: router.selectedVolumeName)
                }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .environment(router)
        .focusedSceneValue(\.windowRouter, router)
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
