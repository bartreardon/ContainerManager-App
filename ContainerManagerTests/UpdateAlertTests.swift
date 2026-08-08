//
//  UpdateAlertTests.swift
//  ContainerManagerTests
//

import Testing

@testable import ContainerManager

/// The old code added buttons in one order and mapped the modal response back to an
/// action by incrementing an index — so a wrong count would silently run the wrong
/// thing, and "update" is not a thing to run by accident. These pin the order the
/// response index is resolved against.
@Suite("UpdateAlert")
struct UpdateAlertTests {
    private func titles(container: String?, app: String?) -> [String] {
        let summary = UpdateSummary(
            title: "Software Update", message: "", container: container, app: app)
        return UpdateAlert.choices(for: summary, store: SystemStore()).map(\.title)
    }

    @Test("A container update offers to install it")
    func containerOnly() {
        #expect(titles(container: "1.2.2", app: nil) == ["Update container…", "Later"])
    }

    @Test("An app update offers the download page")
    func appOnly() {
        #expect(titles(container: nil, app: "1.2.0") == ["Get ContainerManager…", "Later"])
    }

    @Test("Both updates keep container first, then the app, then Later")
    func bothUpdates() {
        #expect(
            titles(container: "1.2.2", app: "1.2.0") == [
                "Update container…", "Get ContainerManager…", "Later",
            ])
    }

    @Test("With nothing to do the only button is OK")
    func nothingToDo() {
        #expect(titles(container: nil, app: nil) == ["OK"])
    }

    @Test("hasUpdate follows whether either version is present")
    func hasUpdate() {
        #expect(UpdateSummary(title: "", message: "", container: "1", app: nil).hasUpdate)
        #expect(UpdateSummary(title: "", message: "", container: nil, app: "1").hasUpdate)
        #expect(UpdateSummary(title: "", message: "", container: nil, app: nil).hasUpdate == false)
    }
}
