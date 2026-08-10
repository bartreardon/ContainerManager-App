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

    /// True when an automatic check is due per the configured frequency.
    static var isUpdateCheckDue: Bool {
        guard let interval = updateCheckFrequency.interval else { return false }
        return Date().timeIntervalSince(lastUpdateCheck) >= interval
    }
}
