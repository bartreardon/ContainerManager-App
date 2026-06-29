//
//  ContainerManagerApp.swift
//  ContainerManager
//
//  Created by Bart E Reardon on 12/6/2026.
//

import SwiftUI

@main
struct ContainerManagerApp: App {
    @State private var systemStore = SystemStore()
    @State private var machinesStore = MachinesStore()
    @State private var containersStore = ContainersStore()
    @State private var imagesStore = ImagesStore()
    @State private var networksStore = NetworksStore()
    @State private var volumesStore = VolumesStore()
    @State private var stacksStore = StacksStore()
    @State private var imageImportModel = ImageImportModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(systemStore)
                .environment(machinesStore)
                .environment(containersStore)
                .environment(imagesStore)
                .environment(networksStore)
                .environment(volumesStore)
                .environment(stacksStore)
                .environment(imageImportModel)
        }
        .commands {
            AppCommands(systemStore: systemStore)
        }
    }
}
