//
//  ListScaffolding.swift
//  ContainerManager
//

import SwiftUI

extension View {
    /// Re-runs `refresh` for as long as the view is on screen, starting immediately.
    ///
    /// The interval is read each tick rather than captured, so changing "Refresh every"
    /// in Settings takes effect on the next one.
    ///
    /// Every list, the menu bar item and the root view hand-rolled this loop. They do
    /// still overlap — the menu bar polls machines and stacks whether or not a window
    /// is showing them — which a per-store "refreshed recently" throttle would cut. Not
    /// done, deliberately: the same `refresh()` is called directly after a create or
    /// delete to show the result, and a throttle would swallow exactly those.
    func autoRefresh(
        every interval: @escaping () -> Duration = { AppDefaults.listRefresh },
        _ refresh: @escaping () async -> Void
    ) -> some View {
        task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: interval())
            }
        }
    }

    /// Runs `action` when the router asks for a new item in `section`, on appear and
    /// whenever the request changes, clearing the request as it's taken.
    ///
    /// The request comes from the File menu and the sidebar's ⌘N, which are handled in
    /// whichever list is on screen.
    func onCreateRequest(for section: SidebarSection, perform action: @escaping () -> Void)
        -> some View
    {
        modifier(CreateRequest(section: section, action: action))
    }
}

private struct CreateRequest: ViewModifier {
    let section: SidebarSection
    let action: () -> Void
    @Environment(WindowRouter.self) private var router

    func body(content: Content) -> some View {
        content
            .onAppear(perform: consume)
            .onChange(of: router.pendingCreate) { consume() }
    }

    private func consume() {
        guard router.pendingCreate == section else { return }
        router.pendingCreate = nil
        action()
    }
}

extension Binding where Value == Bool {
    /// True while `selection` holds anything; setting it false empties the selection.
    ///
    /// The shape every list uses to drive a confirmation dialog from whatever is about
    /// to be acted on, so that the dialog and its subject can't disagree.
    init<Element>(presenceOf selection: Binding<Set<Element>>) {
        self.init(
            get: { !selection.wrappedValue.isEmpty },
            set: { if !$0 { selection.wrappedValue = [] } }
        )
    }
}
