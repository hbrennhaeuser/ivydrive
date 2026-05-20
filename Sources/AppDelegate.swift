import Cocoa
import SwiftUI
import ServiceManagement

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
    private var isMenuOpen = false

    private var cachedAvailability: [UUID: DriveAvailabilityResult] = [:]
    private var isCheckingAvailability = false
    private var liveAvailabilityViews: [UUID: NetworkDriveMenuItemView] = [:]

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "showCapacityLine":           true,
            "showCapacityStats":          true,
            "useBinaryUnits":             false,
            "hideCapacityForReadOnly":    true,
            "groupDrivesByHost":          true,
            "hideConnectedFromAvailable": true,
            "showHoverInfo":              false,
            "hideLocalDrives":            false,
            "clickGroupToConnectAll":       true,
            "clickVolumeToOpenInFinder":    true,
            "didAskAboutLoginItem":         false,
        ])
        notificationManager.configure()
        setupMainMenu()
        setupStatusItem()

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.notificationManager.requestAuthorizationIfNeeded()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.promptForLoginItemIfNeeded()
        }
    }

    private func promptForLoginItemIfNeeded() {
        let ud = UserDefaults.standard
        guard !ud.bool(forKey: "didAskAboutLoginItem") else { return }
        guard SMAppService.mainApp.status == .notRegistered else {
            // Already registered (e.g. user enabled it manually); just mark asked.
            ud.set(true, forKey: "didAskAboutLoginItem")
            return
        }
        ud.set(true, forKey: "didAskAboutLoginItem")

        let alert = NSAlert()
        alert.messageText = "Start MenuBarFS at Login?"
        alert.informativeText = "Would you like MenuBarFS to launch automatically when you log in? You can change this later in Preferences → Maintenance."
        alert.addButton(withTitle: "Enable")
        alert.addButton(withTitle: "Not Now")
        alert.alertStyle = .informational

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            try? SMAppService.mainApp.register()
        }
    }

    // Install a hidden main menu so the responder chain can resolve standard
    // text-editing shortcuts (Cmd+A/C/V/X/Z) in SwiftUI text fields.
    // LSUIElement apps have no visible menu bar, but NSApplication still walks
    // mainMenu when dispatching key equivalents.
    private func setupMainMenu() {
        let editMenu = NSMenu(title: "Edit")
        let editItems: [(String, Selector, String)] = [
            ("Undo",       Selector(("undo:")),       "z"),
            ("Redo",       Selector(("redo:")),       "Z"),
            ("Cut",        #selector(NSText.cut(_:)),        "x"),
            ("Copy",       #selector(NSText.copy(_:)),       "c"),
            ("Paste",      #selector(NSText.paste(_:)),      "v"),
            ("Select All", #selector(NSText.selectAll(_:)),  "a"),
        ]
        for (i, (title, action, key)) in editItems.enumerated() {
            if i == 2 { editMenu.addItem(.separator()) }
            editMenu.addItem(NSMenuItem(title: title, action: action, keyEquivalent: key))
        }

        let editHeader = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editHeader.submenu = editMenu

        let mainMenu = NSMenu()
        mainMenu.addItem(editHeader)
        NSApp.mainMenu = mainMenu
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
        isMenuOpen = true
        rebuildMenu()
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuOpen = false
        DriveInfoPanel.shared.hide()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        liveAvailabilityViews = [:]
        buildNetworkDrivesSection(in: menu, availability: cachedAvailability, isChecking: isCheckingAvailability)
        menu.addItem(.separator())
        buildEjectableVolumesSection(in: menu)
        menu.addItem(.separator())
        buildAppSection(in: menu)

        let unmounted = driveManager.drives.filter { !driveManager.isMounted($0) }
        guard !unmounted.isEmpty, !isCheckingAvailability else { return }
        isCheckingAvailability = true
        DriveAvailabilityChecker.shared.checkAllAsync(unmounted) { [weak self] results in
            guard let self else { return }
            self.cachedAvailability = results
            self.isCheckingAvailability = false
            for (id, result) in results {
                self.liveAvailabilityViews[id]?.updateAvailability(result)
            }
        }
    }

    // MARK: - Menu Sections

    private func buildNetworkDrivesSection(in menu: NSMenu, availability: [UUID: DriveAvailabilityResult], isChecking: Bool) {
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
            for drive in allDrives.sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }) {
                let mounted = connectedIDs.contains(drive.id)
                if hideConnected && mounted { continue }
                addNetworkDriveItem(drive, mounted: mounted, availability: availability, to: menu, indented: false, isChecking: isChecking)
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
        var drivesForKey: [String: [NetworkDrive]] = [:]
        for drive in allDrives {
            drivesForKey[drive.hostGroupKey, default: []].append(drive)
        }
        let keyOrder = drivesForKey.keys.sorted {
            (URL(string: $0)?.host ?? $0).localizedStandardCompare(URL(string: $1)?.host ?? $1) == .orderedAscending
        }

        var addedAny = false
        for key in keyOrder {
            let groupDrives = drivesForKey[key]!.sorted(by: { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending })
            let unconnectedInGroup = groupDrives.filter { !connectedIDs.contains($0.id) }
            let entriesToShow = hideConnected ? unconnectedInGroup : groupDrives
            if entriesToShow.isEmpty { continue }
            addedAny = true

            if groupDrives.count == 1 {
                let drive = groupDrives[0]
                addNetworkDriveItem(drive, mounted: connectedIDs.contains(drive.id), availability: availability, to: menu, indented: false, isChecking: isChecking)
                continue
            }

            // Multi-drive group: header (clickable when any sub-entry is unconnected) + indented sub-entries
            let connectAllEnabled = ud.bool(forKey: "clickGroupToConnectAll")
            let connectAll: (() -> Void)? = (connectAllEnabled && !unconnectedInGroup.isEmpty) ? { [weak self] in
                guard let self else { return }
                for drive in unconnectedInGroup {
                    self.connectDrive(drive)
                }
            } : nil
            let headerItem = NSMenuItem()
            headerItem.view = NetworkGroupHeaderView(
                host: URL(string: key)?.host ?? key,
                onConnect: connectAll,
                showAccentBar: false
            )
            menu.addItem(headerItem)

            for drive in entriesToShow {
                addNetworkDriveItem(drive, mounted: connectedIDs.contains(drive.id), availability: availability, to: menu, indented: true, accented: false, isChecking: isChecking)
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
        indented: Bool,
        accented: Bool = false,
        isChecking: Bool = false
    ) {
        let item = NSMenuItem()
        let view = NetworkDriveMenuItemView(
            drive: drive,
            connected: mounted,
            mountPoint: driveManager.mountPoint(for: drive),
            availability: availability[drive.id],
            operation: activeOperations[drive.id],
            indented: indented,
            showAccentBar: accented,
            isCheckingAvailability: isChecking && !mounted
        ) { [weak self] in
            self?.connectDrive(drive)
        }
        item.view = view
        if !mounted { liveAvailabilityViews[drive.id] = view }
        menu.addItem(item)
    }

    private func buildEjectableVolumesSection(in menu: NSMenu) {
        let ud = UserDefaults.standard
        let allVolumes = VolumeMonitor.ejectableVolumes()
        let volumes = ud.bool(forKey: "hideLocalDrives")
            ? allVolumes.filter { $0.deviceType == .network }
            : allVolumes
        let groupByHost = ud.bool(forKey: "groupDrivesByHost")

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
        let driveID = drive.id
        // Auto-clear stuck connecting state after 30 s.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.activeOperations[driveID] == .connecting else { return }
            self.activeOperations.removeValue(forKey: driveID)
            if self.isMenuOpen { self.rebuildMenu() }
        }
        driveManager.mount(drive) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.activeOperations.removeValue(forKey: drive.id)
                if self.isMenuOpen { self.rebuildMenu() }
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
                if self.isMenuOpen { self.rebuildMenu() }
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
        openPreferences(tab: 4)
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
