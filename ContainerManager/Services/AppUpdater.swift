//
//  AppUpdater.swift
//  ContainerManager
//

import Foundation
import Sparkle

/// ContainerManager's own updates, through Sparkle.
///
/// Checks run on the app's schedule (Settings ▸ Updates) rather than Sparkle's — its
/// automatic checks are off in Info.plist — so one alert can report both the app and
/// container. Installing hands over to Sparkle's window, which downloads, verifies the
/// EdDSA signature, replaces the app and relaunches it.
final class AppUpdater: NSObject {
    static let shared = AppUpdater()

    /// The running app's marketing version (CFBundleShortVersionString).
    static var installedVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    struct NotConfigured: LocalizedError {
        let underlying: any Error
        var errorDescription: String? {
            "This build isn't set up to update itself (\(underlying.localizedDescription))."
        }
    }

    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
    private var started = false
    private var pendingCheck: CheckedContinuation<String?, any Error>?

    /// Sparkle refuses to start without an update key in Info.plist, as in local builds.
    private func start() throws {
        guard !started else { return }
        do {
            try controller.updater.start()
        } catch {
            throw NotConfigured(underlying: error)
        }
        started = true
    }

    /// The newer version on offer, or nil when up to date. Shows no interface.
    func availableVersion() async throws -> String? {
        try start()
        guard pendingCheck == nil else { return nil }
        return try await withCheckedThrowingContinuation { continuation in
            pendingCheck = continuation
            controller.updater.checkForUpdateInformation()
        }
    }

    /// Hands over to Sparkle to download and install the update.
    func installUpdate() {
        guard (try? start()) != nil else { return }
        controller.updater.checkForUpdates()
    }

    private func finishCheck(_ result: Result<String?, any Error>) {
        pendingCheck?.resume(with: result)
        pendingCheck = nil
    }
}

// Sparkle calls its delegate on the main thread.
extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        finishCheck(.success(item.displayVersionString))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: any Error) {
        finishCheck(.success(nil))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        let noUpdate = (error as NSError).domain == SUSparkleErrorDomain
            && (error as NSError).code == Int(SUError.noUpdateError.rawValue)
        finishCheck(noUpdate ? .success(nil) : .failure(error))
    }

    #if DEBUG
    /// Lets a development build test updates against a local feed:
    /// `defaults write com.bartreardon.ContainerManager debugAppcastURL http://localhost:8000/appcast.xml`
    func feedURLString(for updater: SPUUpdater) -> String? {
        UserDefaults.standard.string(forKey: "debugAppcastURL")
    }
    #endif
}
