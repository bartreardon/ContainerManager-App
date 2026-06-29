//
//  RootView.swift
//  ContainerManager
//

import SwiftUI

struct RootView: View {
    @Environment(SystemStore.self) private var systemStore
    @State private var router = WindowRouter()
    @SceneStorage("selectedSection") private var storedSection = SidebarSection.machines.rawValue

    private var windowTitle: String {
        guard let name = router.currentSelectionName else { return router.section.rawValue }
        let shown = router.section == .images ? name.shortImageReference : name
        return "\(router.section.rawValue) — \(shown)"
    }

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
                        StacksListView(selection: $router.selectedStackNames)
                    case .machines:
                        MachinesListView(selection: $router.selectedMachineIds)
                    case .containers:
                        ContainersListView(selection: $router.selectedContainerIds)
                    case .images:
                        ImagesListView(selection: $router.selectedImageReferences)
                    case .networks:
                        NetworksListView(selection: $router.selectedNetworkIds)
                    case .volumes:
                        VolumesListView(selection: $router.selectedVolumeNames)
                    }
                } else {
                    DaemonGateView()
                }
            }
            // The content column owns the window/tab title in a NavigationSplitView,
            // so drive it from here (sidebar section + selected item).
            .navigationTitle(windowTitle)
            .navigationSplitViewColumnWidth(min: 280, ideal: 340)
        } detail: {
            if systemStore.isReady {
                switch router.section {
                case .stacks:
                    detail(router.selectedStackNames) { StackDetailView(stackName: $0) }
                case .machines:
                    detail(router.selectedMachineIds) { MachineDetailView(machineId: $0) }
                case .containers:
                    detail(router.selectedContainerIds) { ContainerDetailView(containerId: $0) }
                case .images:
                    detail(router.selectedImageReferences) { ImageDetailView(reference: $0) }
                case .networks:
                    detail(router.selectedNetworkIds) { NetworkDetailView(networkId: $0) }
                case .volumes:
                    detail(router.selectedVolumeNames) { VolumeDetailView(volumeName: $0) }
                }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: 900, minHeight: 520)
        .environment(router)
        .focusedSceneValue(\.windowRouter, router)
        .onAppear { router.section = SidebarSection(rawValue: storedSection) ?? .machines }
        .onChange(of: router.section) { storedSection = router.section.rawValue }
        .errorAlert($systemStore.lastError)
        .task {
            while !Task.isCancelled {
                await systemStore.refresh()
                let interval: Duration = systemStore.isReady ? .seconds(15) : .seconds(5)
                try? await Task.sleep(for: interval)
            }
        }
    }

    /// Shows the detail for a single selection (or the detail view's own empty state
    /// when nothing is selected); a count placeholder when several items are selected.
    @ViewBuilder
    private func detail<D: View>(_ selection: Set<String>, @ViewBuilder _ make: (String?) -> D) -> some View {
        if selection.count > 1 {
            ContentUnavailableView("\(selection.count) Selected", systemImage: "checklist")
        } else {
            make(selection.first)
        }
    }
}
