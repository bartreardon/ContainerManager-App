//
//  AppDefaults.swift
//  ContainerManager
//

import Foundation

/// How often the app automatically checks GitHub for a newer `container` release.
enum UpdateCheckFrequency: String, CaseIterable, Identifiable {
    case never, launch, daily, weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .never: "Never (manual only)"
        case .launch: "On launch"
        case .daily: "Once a day"
        case .weekly: "Once a week"
        }
    }

    /// Minimum time between automatic checks; nil means never, 0 means every launch.
    var interval: TimeInterval? {
        switch self {
        case .never: nil
        case .launch: 0
        case .daily: 24 * 60 * 60
        case .weekly: 7 * 24 * 60 * 60
        }
    }
}

/// Shared access to user preferences stored in `UserDefaults` (mirrors the
/// `@AppStorage` keys used by SettingsView). Read live inside polling loops so
/// changes take effect on the next refresh.
enum AppDefaults {
    // Every key in one place, so a view and the code reading it behind its back can't
    // drift apart. `containerBinaryPath` belongs to CLIPathResolver, which reads it.
    static let listRefreshKey = "listRefreshSeconds"
    static let statsRefreshKey = "statsRefreshSeconds"
    static let showMenuBarIconKey = "showMenuBarIcon"
    static let updateCheckFrequencyKey = "updateCheckFrequency"
    static let lastUpdateCheckKey = "lastUpdateCheck"

    // Notifications. Off by default: an app that starts talking before being asked is
    // one people silence permanently.
    static let notificationsEnabledKey = "notificationsEnabled"
    static let notifyStopsKey = "notifyUnexpectedStops"
    static let notifyOperationsKey = "notifyOperationsFinished"
    static let notifyThresholdsKey = "notifyThresholds"
    static let watchIntervalKey = "watchIntervalSeconds"
    static let cpuThresholdKey = "cpuThresholdPercent"
    static let freeDiskThresholdKey = "freeDiskThresholdGB"

    /// List auto-refresh interval. Defaults to 5s when unset.
    static var listRefresh: Duration {
        let seconds = UserDefaults.standard.integer(forKey: listRefreshKey)
        return .seconds(Double(seconds == 0 ? 5 : seconds))
    }

    /// Resource-sampling interval, or nil when sampling is switched off.
    ///
    /// Read live on every tick like `listRefresh`, so changing it in Settings takes
    /// effect on the next one. Unlike `listRefresh` this can't lean on `integer(forKey:)`
    /// returning 0 for "unset": 0 is the stored value for Off, and the two have to mean
    /// different things.
    static var statsRefresh: Duration? {
        guard let seconds = UserDefaults.standard.object(forKey: statsRefreshKey) as? Int else {
            return .seconds(2)
        }
        return seconds > 0 ? .seconds(Double(seconds)) : nil
    }

    /// Whether the menu bar item is shown. Defaults to true when unset.
    static var showMenuBarIcon: Bool {
        UserDefaults.standard.object(forKey: showMenuBarIconKey) as? Bool ?? true
    }

    /// Configured automatic update-check cadence. Defaults to weekly.
    static var updateCheckFrequency: UpdateCheckFrequency {
        UpdateCheckFrequency(rawValue: UserDefaults.standard.string(forKey: updateCheckFrequencyKey) ?? "") ?? .weekly
    }

    /// Timestamp of the last update check (manual or automatic).
    static var lastUpdateCheck: Date {
        get { Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: lastUpdateCheckKey)) }
        set { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: lastUpdateCheckKey) }
    }

    /// Master switch. Every other notification setting is read only when this is on.
    static var notificationsEnabled: Bool {
        UserDefaults.standard.bool(forKey: notificationsEnabledKey)
    }

    /// The per-category switches, each defaulting to on once notifications are enabled —
    /// turning the feature on and hearing nothing would read as broken.
    static func notifyCategory(_ key: String) -> Bool {
        guard notificationsEnabled else { return false }
        return UserDefaults.standard.object(forKey: key) as? Bool ?? true
    }

    /// How often the watcher looks. Same shape as `statsRefresh`: 0 is a real value
    /// meaning off, so `object(forKey:)` is needed to tell it from unset.
    static var watchInterval: Duration {
        guard let seconds = UserDefaults.standard.object(forKey: watchIntervalKey) as? Int else {
            return .seconds(30)
        }
        return .seconds(Double(max(5, seconds)))
    }

    /// CPU percent that counts as excessive, where 100% is one core. Nil when off.
    static var cpuThreshold: Double? {
        guard notifyCategory(notifyThresholdsKey) else { return nil }
        let percent = UserDefaults.standard.object(forKey: cpuThresholdKey) as? Int ?? 0
        return percent > 0 ? Double(percent) : nil
    }

    /// Free space below which to warn, in bytes. Nil when off.
    static var freeDiskThreshold: UInt64? {
        guard notifyCategory(notifyThresholdsKey) else { return nil }
        let gigabytes = UserDefaults.standard.object(forKey: freeDiskThresholdKey) as? Int ?? 0
        return gigabytes > 0 ? UInt64(gigabytes) * 1_000_000_000 : nil
    }

    /// True when an automatic check is due per the configured frequency.
    static var isUpdateCheckDue: Bool {
        guard let interval = updateCheckFrequency.interval else { return false }
        return Date().timeIntervalSince(lastUpdateCheck) >= interval
    }
}
