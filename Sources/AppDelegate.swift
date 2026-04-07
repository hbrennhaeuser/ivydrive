import Cocoa
import SwiftUI

enum DriveOperation {
    case connecting, ejecting
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    let driveManager = NetworkDriveManager()
    private let notificationManager = NotificationManager()

    private var preferencesWindow: NSWindow?
    private let preferencesViewModel = PreferencesViewModel()

    /// Keyed by drive UUID (connecting) or volume URL string (ejecting).
    private var activeOperations: [AnyHashable: DriveOperation] = [:]

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "showCapacityLine":          true,
            "showCapacityStats":         true,
            "useBinaryUnits":            false,
            "hideCapacityForReadOnly":   true,
            "groupDrivesByHost":         true,
            "hideConnectedFromAvailable": false,
        ])
        notificationManager.configure()
        setupStatusItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.notificationManager.requestAuthorizationIfNeeded()
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "externaldrive.connected.to.line.below",
                accessibilityDescription: "MenuBarFS"
            )
            button.image?.isTemplate = true
        }

        menu.delegate = self
        statusItem.menu = menu
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        let unmounted = driveManager.drives.filter { !driveManager.isMounted($0) }
        let availability: [UUID: DriveAvailabilityResult]
        if unmounted.isEmpty {
            availability = [:]
        } else {
            availability = DriveAvailabilityChecker.shared.checkAll(unmounted)
        }
        buildNetworkDrivesSection(in: menu, availability: availability)
        menu.addItem(.separator())
        buildEjectableVolumesSection(in: menu)
        menu.addItem(.separator())
        buildAppSection(in: menu)
    }

    func menuDidClose(_ menu: NSMenu) {
        DriveInfoPanel.shared.hide()
    }

    // MARK: - Menu Sections

    private func buildNetworkDrivesSection(in menu: NSMenu, availability: [UUID: DriveAvailabilityResult]) {
        let ud = UserDefaults.standard
        let groupByHost   = ud.bool(forKey: "groupDrivesByHost")
        let hideConnected = ud.bool(forKey: "hideConnectedFromAvailable")
        let allDrives = driveManager.drives

        if allDrives.isEmpty {
            let item = NSMenuItem(title: "No network drives configured", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let connectedIDs = Set(allDrives.filter { driveManager.isMounted($0) }.map { $0.id })

        if !groupByHost {
            var added = false
            for drive in allDrives {
                let mounted = connectedIDs.contains(drive.id)
                if hideConnected && mounted { continue }
                addNetworkDriveItem(drive, mounted: mounted, availability: availability, to: menu, indented: false)
                added = true
            }
            if !added {
                let item = NSMenuItem(title: "All drives connected", action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            }
            return
        }

        // Group by scheme://host:port
        var keyOrder: [String] = []
        var drivesForKey: [String: [NetworkDrive]] = [:]
        for drive in allDrives {
            let key = drive.hostGroupKey
            if drivesForKey[key] == nil { keyOrder.append(key) }
            drivesForKey[key, default: []].append(drive)
        }

        var addedAny = false
        for key in keyOrder {
            let groupDrives = drivesForKey[key]!
            let unconnectedInGroup = groupDrives.filter { !connectedIDs.contains($0.id) }
            let entriesToShow = hideConnected ? unconnectedInGroup : groupDrives
            if entriesToShow.isEmpty { continue }
            addedAny = true

            if groupDrives.count == 1 {
                let drive = groupDrives[0]
                addNetworkDriveItem(drive, mounted: connectedIDs.contains(drive.id), availability: availability, to: menu, indented: false)
                continue
            }

            // Multi-drive group: header (clickable when any sub-entry is unconnected) + indented sub-entries
            let connectAll: (() -> Void)? = unconnectedInGroup.isEmpty ? nil : { [weak self] in
                guard let self else { return }
                for drive in unconnectedInGroup {
                    self.connectDrive(drive)
                }
            }
            let headerItem = NSMenuItem()
            headerItem.view = NetworkGroupHeaderView(
                host: URL(string: key)?.host ?? key,
                onConnect: connectAll
            )
            menu.addItem(headerItem)

            for drive in entriesToShow {
                addNetworkDriveItem(drive, mounted: connectedIDs.contains(drive.id), availability: availability, to: menu, indented: true)
            }
        }

        if !addedAny {
            let item = NSMenuItem(title: "All drives connected", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }
    }

    private func addNetworkDriveItem(
        _ drive: NetworkDrive,
        mounted: Bool,
        availability: [UUID: DriveAvailabilityResult],
        to menu: NSMenu,
        indented: Bool
    ) {
        let item = NSMenuItem()
        let view = NetworkDriveMenuItemView(
            drive: drive,
            connected: mounted,
            mountPoint: driveManager.mountPoint(for: drive),
            availability: availability[drive.id],
            operation: activeOperations[drive.id],
            indented: indented
        ) { [weak self] in
            self?.connectDrive(drive)
        }
        item.view = view
        menu.addItem(item)
    }

    private func buildEjectableVolumesSection(in menu: NSMenu) {
        let volumes = VolumeMonitor.ejectableVolumes()
        let groupByHost = UserDefaults.standard.bool(forKey: "groupDrivesByHost")

        if volumes.isEmpty {
            let item = NSMenuItem(title: "No ejectable volumes", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        let capacities = prefetchCapacities(for: volumes)

        if !groupByHost {
            for volume in volumes {
                addVolumeItem(volume, capacity: capacities[volume.volumeURL], to: menu, indented: false)
            }
            return
        }

        // Local volumes rendered flat first
        for volume in volumes where volume.remoteHost == nil {
            addVolumeItem(volume, capacity: capacities[volume.volumeURL], to: menu, indented: false)
        }

        // Group network volumes by lowercase host
        var hostOrder: [String] = []
        var volumesForHost: [String: [MountedVolume]] = [:]
        for volume in volumes where volume.remoteHost != nil {
            let host = volume.remoteHost!
            if volumesForHost[host] == nil { hostOrder.append(host) }
            volumesForHost[host, default: []].append(volume)
        }

        for host in hostOrder {
            let groupVolumes = volumesForHost[host]!

            if groupVolumes.count == 1 {
                addVolumeItem(groupVolumes[0], capacity: capacities[groupVolumes[0].volumeURL], to: menu, indented: false)
                continue
            }

            // Capacity is shown on the header when every volume in the group
            // has the same total bytes; otherwise it appears on individual entries.
            let groupCapacities = groupVolumes.compactMap { capacities[$0.volumeURL] }
            let allUniform = groupCapacities.count == groupVolumes.count
                && Set(groupCapacities.map { $0.totalBytes }).count == 1

            let headerItem = NSMenuItem()
            headerItem.view = VolumeGroupHeaderView(host: host, capacity: allUniform ? groupCapacities.first : nil)
            menu.addItem(headerItem)

            for volume in groupVolumes {
                addVolumeItem(volume, capacity: allUniform ? nil : capacities[volume.volumeURL], to: menu, indented: true)
            }
        }
    }

    private func addVolumeItem(_ volume: MountedVolume, capacity: VolumeCapacity?, to menu: NSMenu, indented: Bool) {
        let item = NSMenuItem()

        let icon: NSImage
        if volume.deviceType == .network {
            // Avoid icon(forFile:) on network volume paths — it can block when
            // the volume is mounted but the network is unreachable.
            icon = NSImage(
                systemSymbolName: "externaldrive.connected.to.line.below",
                accessibilityDescription: "Network Drive"
            ) ?? NSImage()
        } else {
            icon = NSWorkspace.shared.icon(forFile: volume.path)
        }
        icon.size = NSSize(width: 16, height: 16)

        let view = VolumeMenuItemView(
            icon: icon,
            name: volume.name,
            volumeURL: volume.volumeURL,
            deviceType: volume.deviceType,
            capacity: capacity,
            operation: activeOperations[volume.volumeURL.absoluteString],
            indented: indented
        ) { [weak self] in
            self?.ejectVolume(named: volume.name, at: volume.volumeURL)
        }
        item.view = view
        item.toolTip = "Click to eject \(volume.name)"
        menu.addItem(item)
    }

    /// Fetches capacity for all volumes in parallel. Waits at most 200 ms for the
    /// whole batch — fast enough to be imperceptible, long enough for most reachable
    /// network drives. Volumes that don't respond in time simply get no capacity bar.
    private func prefetchCapacities(for volumes: [MountedVolume]) -> [URL: VolumeCapacity] {
        let ud = UserDefaults.standard
        guard ud.bool(forKey: "showCapacityLine") else { return [:] }
        let hideForReadOnly = ud.bool(forKey: "hideCapacityForReadOnly")

        var results = [URL: VolumeCapacity]()
        let lock = NSLock()
        let group = DispatchGroup()

        for volume in volumes {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                defer { group.leave() }
                let keys: Set<URLResourceKey> = [
                    .volumeTotalCapacityKey,
                    .volumeAvailableCapacityKey,
                    .volumeIsReadOnlyKey,
                ]
                guard let vals = try? volume.volumeURL.resourceValues(forKeys: keys),
                      let total = vals.volumeTotalCapacity,
                      let free  = vals.volumeAvailableCapacity,
                      total > 0 else { return }
                let isRO = vals.volumeIsReadOnly ?? false
                if hideForReadOnly && isRO { return }
                lock.lock()
                results[volume.volumeURL] = VolumeCapacity(usedBytes: total - free, totalBytes: total, isReadOnly: isRO)
                lock.unlock()
            }
        }

        _ = group.wait(timeout: .now() + 0.2)
        return results
    }

    private func buildAppSection(in menu: NSMenu) {
        let prefsItem = NSMenuItem(
            title: "Preferences\u{2026}",
            action: #selector(showPreferences),
            keyEquivalent: ","
        )
        prefsItem.target = self
        menu.addItem(prefsItem)

        let aboutItem = NSMenuItem(
            title: "About MenuBarFS",
            action: #selector(showAbout),
            keyEquivalent: ""
        )
        aboutItem.target = self
        menu.addItem(aboutItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit MenuBarFS",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = NSApp
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    private func connectDrive(_ drive: NetworkDrive) {
        activeOperations[drive.id] = .connecting
        // Auto-clear stuck connecting state after 30 s.
        let driveID = drive.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.activeOperations[driveID] == .connecting else { return }
            self.activeOperations.removeValue(forKey: driveID)
        }
        driveManager.mount(drive) { [weak self] _ in
            DispatchQueue.main.async {
                self?.activeOperations.removeValue(forKey: drive.id)
            }
        }
    }

    private func ejectVolume(named volumeName: String, at url: URL) {
        activeOperations[url.absoluteString] = .ejecting
        FileManager.default.unmountVolume(
            at: url,
            options: [.allPartitionsAndEjectDisk]
        ) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeOperations.removeValue(forKey: url.absoluteString)
                if let error {
                    self.notificationManager.showEjectFailed(volumeName, details: error.localizedDescription)
                } else {
                    self.notificationManager.showEjected(volumeName)
                }
            }
        }
    }

    @objc private func showPreferences() {
        openPreferences(tab: 0)
    }

    @objc private func showAbout() {
        openPreferences(tab: 2)
    }

    private func openPreferences(tab: Int) {
        preferencesViewModel.selectedTab = tab
        if preferencesWindow == nil {
            let view = PreferencesView(manager: driveManager, viewModel: preferencesViewModel)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 490),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MenuBarFS Preferences"
            window.contentView = NSHostingView(rootView: view)
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        }
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
