//
//  AppDefaults.swift
//  ContainerManager
//

import Foundation

/// Shared access to user preferences stored in `UserDefaults` (mirrors the
/// `@AppStorage` keys used by SettingsView). Read live inside polling loops so
/// changes take effect on the next refresh.
enum AppDefaults {
    /// List auto-refresh interval. Defaults to 5s when unset.
    static var listRefresh: Duration {
        let seconds = UserDefaults.standard.integer(forKey: "listRefreshSeconds")
        return .seconds(Double(seconds == 0 ? 5 : seconds))
    }
}
