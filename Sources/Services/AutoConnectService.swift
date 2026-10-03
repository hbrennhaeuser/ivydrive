import Foundation
import Network

final class AutoConnectService {
    private weak var driveManager: NetworkDriveManager?
    private weak var notificationManager: NotificationManager?

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.hbrennhaeuser.ivydrive.autoconnect.monitor")
    private var previousPath: NWPath?

    // Cancelled and replaced on each new trigger; ensures at most one pending attempt.
    private var pendingWork: DispatchWorkItem?

    /// Absolute time when the pending autoconnect will fire. Nil when idle.
    private(set) var pendingFireTime: Date?

    // Drive IDs recently ejected by the user; autoconnect is suppressed for 5 minutes.
    private var suppressedIDs: Set<UUID> = []

    init(driveManager: NetworkDriveManager, notificationManager: NotificationManager) {
        self.driveManager = driveManager
        self.notificationManager = notificationManager
    }

    func start() {
        schedule(delay: 15, trigger: .startup)

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            defer { self.previousPath = path }
            // Skip initial report (previousPath == nil) — startup trigger covers that case.
            // Only fire on satisfied transitions or interface changes while satisfied.
            guard path.status == .satisfied,
                  let prev = self.previousPath,
                  path != prev else { return }
            DispatchQueue.main.async {
                self.schedule(delay: 3, trigger: .networkChange)
            }
        }
        monitor.start(queue: monitorQueue)
    }

    /// Suppresses autoconnect for a drive for 5 minutes (call after user-initiated eject).
    func suppressAutoConnect(for driveID: UUID) {
        suppressedIDs.insert(driveID)
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) { [weak self] in
            self?.suppressedIDs.remove(driveID)
        }
    }

    // MARK: - Private

    private enum Trigger { case startup, networkChange }

    private func schedule(delay: TimeInterval, trigger: Trigger) {
        pendingWork?.cancel()
        pendingFireTime = Date().addingTimeInterval(delay)
        let work = DispatchWorkItem { [weak self] in
            self?.pendingFireTime = nil
            self?.runAutoConnect(trigger: trigger)
        }
        pendingWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func runAutoConnect(trigger: Trigger) {
        guard let driveManager else { return }

        let candidates = driveManager.drives.filter { drive in
            guard drive.autoConnect else { return false }
            guard !suppressedIDs.contains(drive.id) else { return false }
            guard !driveManager.isMounted(drive) else { return false }
            switch trigger {
            case .startup:       return drive.autoConnectOnStartup
            case .networkChange: return drive.autoConnectOnNetworkChange
            }
        }
        guard !candidates.isEmpty else { return }

        let needsCheck = candidates.filter {
            $0.checkDNSResolution || $0.checkHostReachability || $0.checkPortAvailability
        }
        let checkFree = candidates.filter {
            !$0.checkDNSResolution && !$0.checkHostReachability && !$0.checkPortAvailability
        }

        for drive in checkFree { mountSilently(drive) }

        guard !needsCheck.isEmpty else { return }
        DriveAvailabilityChecker.shared.checkAllAsync(needsCheck) { [weak self] results in
            guard let self, let driveManager = self.driveManager else { return }
            for drive in needsCheck {
                guard let result = results[drive.id], result.dotIsTeal else { continue }
                guard !driveManager.isMounted(drive) else { continue }
                self.mountSilently(drive)
            }
        }
    }

    private func mountSilently(_ drive: NetworkDrive) {
        driveManager?.mountSilently(drive) { [weak self] outcome in
            if case .mounted = outcome {
                self?.notificationManager?.showConnected(drive.displayName)
            }
        }
    }
}
