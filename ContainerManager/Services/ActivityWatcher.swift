//
//  ActivityWatcher.swift
//  ContainerManager
//

import ContainerResource
import Foundation
import MachineAPIClient

/// Watches for the things worth interrupting someone about, and posts notifications.
///
/// Runs for the app's lifetime rather than a view's, which is the whole point: the
/// moments worth knowing about — a container exiting, a build finishing, the disk filling
/// — are the ones where nobody is looking at the app. That rules out `.autoRefresh`
/// (`Views/Shared/ListScaffolding.swift`), which lives exactly as long as a view, and the
/// `MenuBarLabel` loop, which stops with the menu bar item and never polls containers.
///
/// It does nothing at all until notifications are switched on, so the idle cost of the
/// feature is one sleeping task.
@Observable
@MainActor
final class ActivityWatcher {
    private let system: SystemStore
    private let containers: ContainersStore
    private let machines: MachinesStore
    private let stacks: StacksStore
    private let stats: StatsStore

    private var policy = NotificationPolicy()
    private var loop: Task<Void, Never>?
    /// Whether the last tick found notifications switched on, so the baseline can be
    /// reset when they're switched back on rather than reporting a backlog.
    private var wasEnabled = false
    private var systemWasReady = false

    init(
        system: SystemStore, containers: ContainersStore, machines: MachinesStore,
        stacks: StacksStore, stats: StatsStore
    ) {
        self.system = system
        self.containers = containers
        self.machines = machines
        self.stacks = stacks
        self.stats = stats
        start()
    }

    private func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.tick()
                try? await Task.sleep(for: AppDefaults.watchInterval)
            }
        }
    }

    // MARK: One pass

    private func tick() async {
        guard AppDefaults.notificationsEnabled else {
            // Forget everything, so switching notifications back on doesn't announce
            // every change that happened while they were off.
            if wasEnabled {
                policy.rebaseline()
                stats.setBackgroundIds([])
                wasEnabled = false
            }
            return
        }
        if !wasEnabled {
            // Normally the Settings toggle has already asked. This covers the cases it
            // doesn't: settings restored from a backup, set by a profile, or written
            // directly. Posting without authorisation fails silently, which would look
            // exactly like the feature not working.
            if await !Notifier.isAuthorized() {
                await Notifier.requestAuthorization()
            }
            policy.rebaseline()
        }
        wasEnabled = true

        await refreshState()
        let now = Date()

        checkServices(now: now)
        checkStops(now: now)
        checkStacks(now: now)
        checkThresholds(now: now)
        checkDisk(now: now)
    }

    /// Refreshes only what the checks need. The lists refresh themselves when a window is
    /// open; this is for when one isn't.
    private func refreshState() async {
        await system.refresh()
        guard system.isReady else { return }
        await containers.refresh()
        await machines.refresh()
        await stacks.refresh()
    }

    // MARK: Checks

    private func checkServices(now: Date) {
        let ready = system.isReady
        defer { systemWasReady = ready }
        guard systemWasReady, !ready, AppDefaults.notifyCategory(AppDefaults.notifyStopsKey) else {
            return
        }
        guard policy.allow("services", now: now) else { return }
        Notifier.post(
            identifier: "services",
            title: "Container services stopped",
            body: "Containers and machines aren't running. Open ContainerManager to start them again.")
    }

    private func checkStops(now: Date) {
        guard AppDefaults.notifyCategory(AppDefaults.notifyStopsKey) else { return }

        let running = Set(containers.containers.filter { $0.status == .running }.map(\.id))
        let busy = Set(containers.containers.map(\.id).filter { containers.isBusy($0) })
        let stopped = policy.stopped(kind: .container, running: running, busy: busy)

        // A stack going down is one event about the stack, not one per service.
        let stackOf = { [stacks] (id: String) -> String? in
            stacks.stacks.first { $0.services.contains { $0.id == id } }?.displayName
        }
        let (byStack, loose) = coalescedByStack(stopped, stackOf: stackOf)

        for (stack, count) in byStack.sorted(by: { $0.key < $1.key }) {
            guard policy.allow("stopped.stack.\(stack)", now: now) else { continue }
            Notifier.post(
                identifier: "stopped.stack.\(stack)",
                title: "\(stack) stopped",
                body: count == 1
                    ? "A service stopped on its own." : "\(count) services stopped on their own.",
                section: .stacks, item: stack)
        }
        for id in loose {
            guard policy.allow("stopped.container.\(id)", now: now) else { continue }
            Notifier.post(
                identifier: "stopped.container.\(id)",
                title: "\(id) stopped",
                body: "The container stopped on its own.",
                section: .containers, item: id)
        }

        let machinesRunning = Set(machines.machines.filter { $0.status == .running }.map(\.id))
        let machinesBusy = Set(machines.machines.map(\.id).filter { machines.isBusy($0) })
        for id in policy.stopped(kind: .machine, running: machinesRunning, busy: machinesBusy) {
            guard policy.allow("stopped.machine.\(id)", now: now) else { continue }
            Notifier.post(
                identifier: "stopped.machine.\(id)",
                title: "\(id) stopped",
                body: "The machine stopped on its own.",
                section: .machines, item: id)
        }
    }

    private func checkStacks(now: Date) {
        guard AppDefaults.notifyCategory(AppDefaults.notifyStopsKey) else { return }
        for stack in stacks.stacks where stack.anyRunning && !stack.allRunning {
            let missing = stacks.missingServices(in: stack).count
            guard missing > 0, policy.allow("incomplete.\(stack.name)", now: now) else { continue }
            Notifier.post(
                identifier: "incomplete.\(stack.name)",
                title: "\(stack.displayName) is incomplete",
                body: missing == 1
                    ? "One service isn't running." : "\(missing) services aren't running.",
                section: .stacks, item: stack.name)
        }
    }

    private func checkThresholds(now: Date) {
        guard let limit = AppDefaults.cpuThreshold else {
            stats.setBackgroundIds([])
            return
        }
        // Thresholds need readings for containers no view is watching, so the watcher
        // holds its own claim on the sampler.
        let running = containers.containers.filter { $0.status == .running }
        stats.setBackgroundIds(Set(running.map(\.id)))

        for container in running {
            let id = container.id
            if stats.isNotResponding(id), policy.allow("quiet.\(id)", now: now) {
                Notifier.post(
                    identifier: "quiet.\(id)",
                    title: "\(id) isn't responding",
                    body: "It's still running but has stopped answering. It may be out of memory.",
                    section: .containers, item: id)
            }
            guard let cpu = stats.series(for: id)?.latest?.cpuPercent else { continue }
            if policy.crossed("cpu.\(id)", value: cpu, limit: limit, now: now) {
                Notifier.post(
                    identifier: "over.cpu.\(id)",
                    title: "\(id) is busy",
                    body: "Using \(Int(cpu.rounded()))% CPU — you asked to be told at \(Int(limit))%.",
                    section: .containers, item: id)
            }
        }
    }

    private func checkDisk(now: Date) {
        guard let limit = AppDefaults.freeDiskThreshold,
            let free = Self.freeSpaceForContainerStore(),
            free < limit,
            policy.allow("disk", now: now)
        else { return }
        Notifier.post(
            identifier: "disk",
            title: "Low disk space",
            body: "\(Format.bytes(free)) free. Images and containers may fail to be created.")
    }

    /// Free space on the volume holding the container store, which is the number that
    /// actually decides whether a pull succeeds.
    private static func freeSpaceForContainerStore() -> UInt64? {
        let store = URL.homeDirectory.appending(
            path: "Library/Application Support/com.apple.container", directoryHint: .isDirectory)
        let values = try? store.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage.map(UInt64.init)
    }
}
