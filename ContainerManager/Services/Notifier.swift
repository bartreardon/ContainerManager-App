//
//  Notifier.swift
//  ContainerManager
//

import AppKit
import UserNotifications

/// Posts system notifications, and owns the awkward parts of doing so.
///
/// Authorisation is requested when someone turns notifications *on*, not at launch. An
/// app that asks on first run — before it has ever had anything to say — is one people
/// deny out of hand, and macOS gives no second chance without a trip to System Settings.
enum Notifier {
    /// Identifies the app's notifications so a tap can be routed back to the right thing.
    static let sectionKey = "section"
    static let itemKey = "item"

    private static var center: UNUserNotificationCenter { .current() }

    /// Asks for permission, returning whether we ended up with it.
    ///
    /// Called from the Settings toggle: if this returns false the switch goes back off,
    /// rather than leaving the app silently configured to do something it can't.
    @discardableResult
    static func requestAuthorization() async -> Bool {
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    /// Whether the system will actually deliver anything.
    static func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        return settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
    }

    /// Posts one notification.
    ///
    /// `identifier` is the event's subject, so a repeat about the same container replaces
    /// the earlier banner in Notification Centre instead of stacking up beside it.
    static func post(
        identifier: String, title: String, body: String,
        section: SidebarSection? = nil, item: String? = nil
    ) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        var info: [String: String] = [:]
        if let section { info[sectionKey] = section.rawValue }
        if let item { info[itemKey] = item }
        content.userInfo = info

        // nil trigger means deliver now.
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        center.add(request)
    }
}

/// Tells you a long job finished — but only if you're not already watching it.
///
/// The test is whether the app is frontmost, not whether the sheet is open: someone
/// staring at a build log doesn't need a banner saying the build ended, and someone who
/// switched to another app does.
enum OperationNotice {
    static func finished(
        _ title: String, detail: String, succeeded: Bool,
        section: SidebarSection? = nil, item: String? = nil
    ) {
        guard AppDefaults.notifyCategory(AppDefaults.notifyOperationsKey) else { return }
        guard !NSApp.isActive else { return }
        Notifier.post(
            identifier: "operation.\(title)",
            title: succeeded ? title : "\(title) failed",
            body: detail, section: section, item: item)
    }
}
