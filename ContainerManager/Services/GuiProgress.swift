//
//  GuiProgress.swift
//  ContainerManager
//

import Foundation
import Observation
import TerminalProgress

/// Reduces `ProgressUpdateEvent` streams from the container clients into
/// observable state a SwiftUI progress bar can render.
@Observable
final class GuiProgress {
    private(set) var phase: String = ""
    private(set) var subDescription: String = ""
    private(set) var itemsName: String = ""
    private(set) var items: Int = 0
    private(set) var totalItems: Int = 0
    private(set) var size: Int64 = 0
    private(set) var totalSize: Int64 = 0

    var fraction: Double? {
        if totalSize > 0 {
            return min(1, Double(size) / Double(totalSize))
        }
        if totalItems > 0 {
            return min(1, Double(items) / Double(totalItems))
        }
        return nil
    }

    var detail: String {
        if totalSize > 0 {
            return "\(Format.bytes(size)) of \(Format.bytes(totalSize))"
        }
        if totalItems > 0 {
            let name = itemsName.isEmpty ? "items" : itemsName
            return "\(items) of \(totalItems) \(name)"
        }
        return subDescription
    }

    func setPhase(_ description: String) {
        phase = description
        subDescription = ""
        items = 0
        totalItems = 0
        size = 0
        totalSize = 0
    }

    nonisolated var handler: ProgressUpdateHandler {
        { [weak self] events in
            await self?.apply(events)
        }
    }

    private func apply(_ events: [ProgressUpdateEvent]) {
        for event in events {
            switch event {
            case .setDescription(let value): setPhase(value)
            case .setSubDescription(let value): subDescription = value
            case .setItemsName(let value): itemsName = value
            case .addItems(let value): items += value
            case .setItems(let value): items = value
            case .addTotalItems(let value): totalItems += value
            case .setTotalItems(let value): totalItems = value
            case .addSize(let value): size += value
            case .setSize(let value): size = value
            case .addTotalSize(let value): totalSize += value
            case .setTotalSize(let value): totalSize = value
            default: break
            }
        }
    }
}
