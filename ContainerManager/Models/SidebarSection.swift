//
//  SidebarSection.swift
//  ContainerManager
//

import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case stacks = "Stacks"
    case machines = "Machines"
    case containers = "Containers"
    case images = "Images"
    case networks = "Networks"
    case volumes = "Volumes"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .stacks: "square.stack.3d.up"
        case .machines: "desktopcomputer"
        case .containers: "shippingbox"
        case .images: "opticaldiscdrive"
        case .networks: "network"
        case .volumes: "externaldrive"
        }
    }
}
