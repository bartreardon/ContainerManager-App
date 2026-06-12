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

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(systemStore)
                .environment(machinesStore)
                .environment(containersStore)
                .environment(imagesStore)
        }
    }
}
