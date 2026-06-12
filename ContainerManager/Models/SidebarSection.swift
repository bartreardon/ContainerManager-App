//
//  SidebarSection.swift
//  ContainerManager
//

import Foundation

enum SidebarSection: String, CaseIterable, Identifiable {
    case machines = "Machines"
    case containers = "Containers"
    case images = "Images"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .machines: "desktopcomputer"
        case .containers: "shippingbox"
        case .images: "opticaldiscdrive"
        }
    }
}
