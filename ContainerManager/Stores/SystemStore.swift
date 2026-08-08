//
//  SystemStore.swift
//  ContainerManager
//

import AppKit
import ContainerAPIClient
import ContainerPersistence
import ContainerPlugin
import Foundation
import Observation
import struct Containerization.SystemPlatform

/// Tracks whether the `container` system services are installed, up to date, running,
/// and provisioned with a base Linux environment. All other stores gate on this.
@Observable
final class SystemStore {
    static let apiServerLabel = "com.apple.container.apiserver"

    private(set) var status: DaemonStatus = .unknown
    private(set) var health: SystemHealth?
    /// Streamed output from `system start` / repair.
    private(set) var actionOutput: [String] = []
    /// Short progress message during install.
    private(set) var busyMessage: String?
    var lastError: PresentedError?
    /// A pending update message for the interface to present. The store decides what
    /// there is to say and what can be done about it; the view decides how it looks.
    var updateSummary: UpdateSummary?

    /// Latest container release available on GitHub when it's newer than the installed
    /// CLI; nil when up to date or unknown. Drives the passive "update available" badge.
    private(set) var availableUpdate: String?
    /// Latest ContainerManager release when newer than the running app; nil otherwise.
    private(set) var availableAppUpdate: String?
    private var appReleasePageURL: URL?

    private var cachedCLIVersion: String?
    private var didAutoCheckThisLaunch = false

    /// Installed container version for display, from live services or the last CLI probe.
    var installedContainerVersion: String? {
        if let health { return displayVersion(health.apiServerVersion) }
        if let cachedCLIVersion { return displayVersion(cachedCLIVersion) }
        return nil
    }

    /// Fully ready to manage containers (running + base environment present).
    var isReady: Bool { status == .running }

    var isOutdated: Bool {
        if case .outdated = status { return true }
        return false
    }

    func refresh() async {
        switch status {
        case .starting, .stopping, .installing: return
        default: break
        }

        guard CLIRunner.isInstalled else {
            status = .notInstalled
            health = nil
            return
        }

        let label = Self.apiServerLabel
        let registered = await Task.detached {
            (try? ServiceManager.isRegistered(fullServiceLabel: label)) ?? false
        }.value

        if registered, let health = try? await ClientHealthCheck.ping(timeout: .seconds(3)) {
            CLIPathResolver.observe(health: health)
            self.health = health
            guard ContainerVersion.meetsMinimum(health.apiServerVersion) else {
                status = .outdated(displayVersion(health.apiServerVersion))
                return
            }
            status = await baseEnvironmentReady() ? .running : .baseEnvMissing
            return
        }

        health = nil
        if let version = await cliVersion(), !ContainerVersion.meetsMinimum(version) {
            status = .outdated(displayVersion(version))
            return
        }
        status = .stopped
    }

    // MARK: Actions

    func start() async {
        guard status == .stopped || status == .unknown else { return }
        await performStart(stopFirst: false)
    }

    /// Re-runs `system start` (after a stop) to install a missing kernel / base filesystem.
    func repair() async {
        guard status == .baseEnvMissing else { return }
        await performStart(stopFirst: true)
    }

    func stop() async {
        guard status == .running || status == .baseEnvMissing else { return }
        status = .stopping
        do {
            let result = try await CLIRunner.run(["system", "stop"])
            if result.exitCode != 0 {
                lastError = PresentedError(title: "Failed to stop container services", message: result.output)
            }
        } catch {
            lastError = PresentedError(title: "Failed to stop container services", error: error)
        }
        status = .unknown
        health = nil
        await refresh()
    }

    /// Downloads and launches the official installer, then waits for the CLI to appear.
    func install() async {
        guard status == .notInstalled || isOutdated else { return }
        await performInstall()
    }

    private func performInstall() async {
        status = .installing
        actionOutput = []
        busyMessage = "Finding the latest release…"
        do {
            let release = try await ContainerInstaller.latestRelease()
            busyMessage = "Downloading container \(release.version)…"
            let pkg = try await ContainerInstaller.download(release)
            busyMessage = "Opening the installer — complete it in the Installer window."
            ContainerInstaller.launchInstaller(pkg: pkg)

            // Wait (bounded) for the user to finish in Installer.app.
            cachedCLIVersion = nil
            for _ in 0..<120 {
                try? await Task.sleep(for: .seconds(3))
                cachedCLIVersion = nil
                if CLIRunner.isInstalled, let v = await cliVersion(), ContainerVersion.meetsMinimum(v) {
                    break
                }
            }
        } catch {
            lastError = PresentedError(title: "Installation failed", error: error)
        }
        busyMessage = nil
        status = .unknown
        await refresh()
    }

    // MARK: Updates

    /// Outcome of checking one component against its latest GitHub release.
    private enum UpdateOutcome {
        case upToDate(String)   // installed version
        case available(String)  // newer version
        case unknown(String)    // reason it couldn't be determined

        var isUpdate: Bool { if case .available = self { return true }; return false }

        /// The newer version, when there is one.
        var availableVersion: String? {
            if case .available(let version) = self { return version }
            return nil
        }
    }

    /// Checks both ContainerManager and the container tool against their latest GitHub
    /// releases. A manual check (`force`) reports a summary in an alert; automatic checks
    /// just refresh the passive badges. Records the check time for the frequency throttle.
    func checkForUpdates(force: Bool) async {
        async let containerCheck = checkContainerUpdate()
        async let appCheck = checkAppUpdate()
        let (container, app) = await (containerCheck, appCheck)
        AppDefaults.lastUpdateCheck = Date()
        if force { presentUpdateSummary(app: app, container: container) }
    }

    private func checkContainerUpdate() async -> UpdateOutcome {
        guard let current = await cliVersion(), ContainerVersion.parse(current) != nil else {
            availableUpdate = nil
            return .unknown("container isn’t installed")
        }
        do {
            let release = try await ContainerInstaller.latestRelease()
            if ContainerVersion.isUpdate(latest: release.version, over: current) {
                let version = displayVersion(release.version)
                availableUpdate = version
                return .available(version)
            }
            availableUpdate = nil
            return .upToDate(displayVersion(current))
        } catch {
            return .unknown(PresentedError.describe(error))
        }
    }

    private func checkAppUpdate() async -> UpdateOutcome {
        let current = AppUpdateChecker.installedVersion
        do {
            let release = try await AppUpdateChecker.latestRelease()
            if ContainerVersion.isUpdate(latest: release.version, over: current) {
                let version = displayVersion(release.version)
                availableAppUpdate = version
                appReleasePageURL = release.pageURL
                return .available(version)
            }
            availableAppUpdate = nil
            return .upToDate(displayVersion(current))
        } catch {
            return .unknown(PresentedError.describe(error))
        }
    }

    /// Runs one automatic check per launch if the configured frequency says one is due.
    func autoCheckForUpdatesIfDue() async {
        guard !didAutoCheckThisLaunch else { return }
        didAutoCheckThisLaunch = true
        guard AppDefaults.isUpdateCheckDue else { return }
        await checkForUpdates(force: false)
    }

    /// Offers to update to the already-detected available container release (badge/Settings).
    func promptUpdate() {
        guard let availableUpdate else { return }
        updateSummary = UpdateSummary(
            title: "Update Available",
            message: "container \(availableUpdate) is available. Update now?",
            container: availableUpdate,
            app: nil)
    }

    /// Opens the ContainerManager release page for a manual download (no self-update).
    func openAppReleasePage() {
        NSWorkspace.shared.open(appReleasePageURL ?? AppUpdateChecker.releasesPage)
    }

    /// Applies a container update by reinstalling the latest release. Stops services so the
    /// installer can replace files cleanly, then — the farmer's-gate rule — restarts them
    /// afterwards only if they were running before the update.
    func applyUpdate() async {
        let wasRunning = status == .running || status == .baseEnvMissing
        if wasRunning {
            _ = try? await CLIRunner.run(["system", "stop"])
            health = nil
        }
        availableUpdate = nil
        await performInstall()
        if wasRunning {
            await performStart(stopFirst: false)
        }
    }

    private func presentUpdateSummary(app: UpdateOutcome, container: UpdateOutcome) {
        updateSummary = UpdateSummary(
            title: "Software Update",
            message: """
                ContainerManager — \(summaryLine(app))
                Apple container — \(summaryLine(container))
                """,
            container: container.availableVersion,
            app: app.availableVersion)
    }

    private func summaryLine(_ outcome: UpdateOutcome) -> String {
        switch outcome {
        case .upToDate(let version): "\(version) (up to date)"
        case .available(let version): "\(version) available"
        case .unknown(let reason): "couldn’t check — \(reason)"
        }
    }

    // MARK: Helpers

    private func performStart(stopFirst: Bool) async {
        status = .starting
        actionOutput = []
        do {
            if stopFirst {
                _ = try? await CLIRunner.run(["system", "stop"])
            }
            // --enable-kernel-install answers the CLI's interactive kernel prompt.
            // The first start downloads a kernel and base filesystem; no timeout here.
            let result = try await CLIRunner.run(["system", "start", "--enable-kernel-install"]) { [weak self] line in
                self?.actionOutput.append(line)
            }
            if result.exitCode != 0 {
                lastError = PresentedError(title: "Failed to start container services", message: result.output)
            }
        } catch {
            lastError = PresentedError(title: "Failed to start container services", error: error)
        }
        status = .unknown
        await refresh()
    }

    /// The base Linux environment is ready when a default kernel is configured.
    ///
    /// We deliberately do *not* require the init-filesystem (`vminit`) image to be
    /// present. The daemon fetches it on demand the first time a container or machine
    /// is created (`ClientImage.fetch` in the create path), so a fresh, fully working
    /// install legitimately has no `vminit` image yet. Gating on it produced a deadlock:
    /// the UI hid the create actions behind a "Repair" wall, but the only thing that
    /// pulls `vminit` is creating something — so the wall could never be cleared from
    /// the app (only from the terminal). The kernel, by contrast, is a genuine
    /// prerequisite — machine/container boot calls `getDefaultKernel` and fails without
    /// one — and it's installed up front by `system start --enable-kernel-install`, so a
    /// missing kernel is the real, Repair-able "base environment" problem.
    private func baseEnvironmentReady() async -> Bool {
        do {
            _ = try await ClientKernel.getDefaultKernel(for: SystemPlatform.current)
            return true
        } catch {
            return false
        }
    }

    private func cliVersion() async -> String? {
        if let cachedCLIVersion { return cachedCLIVersion }
        guard CLIRunner.isInstalled else { return nil }
        let output = try? await CLIRunner.run(["--version"]).output
        cachedCLIVersion = output?.trimmingCharacters(in: .whitespacesAndNewlines)
        return cachedCLIVersion
    }

    private func displayVersion(_ raw: String) -> String {
        if let v = ContainerVersion.parse(raw) {
            return "\(v.0).\(v.1).\(v.2)"
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
