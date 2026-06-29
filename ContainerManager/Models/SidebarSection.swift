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

    /// Label for the "create new item" action in menus and context menus.
    var newItemLabel: String {
        switch self {
        case .stacks: "New Stack…"
        case .machines: "New Machine…"
        case .containers: "New Container…"
        case .images: "Build Image…"
        case .networks: "New Network…"
        case .volumes: "New Volume…"
        }
    }

    /// Singular noun for menu titles (e.g. the File ▸ New submenu).
    var singularName: String {
        switch self {
        case .stacks: "Stack"
        case .machines: "Machine"
        case .containers: "Container"
        case .images: "Image"
        case .networks: "Network"
        case .volumes: "Volume"
        }
    }
}
