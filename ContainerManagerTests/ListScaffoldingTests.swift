//
//  ListScaffoldingTests.swift
//  ContainerManagerTests
//

import SwiftUI
import Testing

@testable import ContainerManager

/// `Binding(presenceOf:)` drives every list's delete confirmation from the set of
/// things about to be deleted. If dismissing stopped clearing that set, the dialog
/// would reopen on the next redraw; if it cleared the wrong way, a confirmed delete
/// could act on an empty selection.
@Suite("Binding(presenceOf:)")
struct ListScaffoldingTests {
    @Test("Presence follows whether the selection holds anything")
    func presenceFollowsSelection() {
        var selection: Set<String> = []
        let binding = Binding(presenceOf: Binding(get: { selection }, set: { selection = $0 }))

        #expect(binding.wrappedValue == false)
        selection = ["one"]
        #expect(binding.wrappedValue)
        selection = ["one", "two"]
        #expect(binding.wrappedValue)
    }

    @Test("Dismissing clears the selection")
    func dismissingClears() {
        var selection: Set<String> = ["one", "two"]
        let binding = Binding(presenceOf: Binding(get: { selection }, set: { selection = $0 }))

        binding.wrappedValue = false
        #expect(selection.isEmpty)
        #expect(binding.wrappedValue == false)
    }

    @Test("Setting it true leaves the selection alone")
    func presentingDoesNotInvent() {
        // Nothing should be able to raise the dialog without a subject — presentation
        // follows the selection, never the other way round.
        var selection: Set<String> = []
        let binding = Binding(presenceOf: Binding(get: { selection }, set: { selection = $0 }))

        binding.wrappedValue = true
        #expect(selection.isEmpty)
        #expect(binding.wrappedValue == false)
    }
}
