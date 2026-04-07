import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    let driveManager = NetworkDriveManager()
    private let notificationManager = NotificationManager()

    private var preferencesWindow: NSWindow?
    private let preferencesViewModel = PreferencesViewModel()

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            "showCapacityLine":          true,
            "showCapacityStats":         true,
            "useBinaryUnits":            false,
            "hideCapacityForReadOnly":   true,
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
        if driveManager.drives.isEmpty {
            let item = NSMenuItem(title: "No network drives configured", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        for drive in driveManager.drives {
            let mounted = driveManager.isMounted(drive)
            let item = NSMenuItem()

            let view = NetworkDriveMenuItemView(
                drive: drive,
                connected: mounted,
                mountPoint: driveManager.mountPoint(for: drive),
                availability: availability[drive.id]
            ) { [weak self] in
                self?.connectDrive(drive)
            }
            item.view = view
            menu.addItem(item)
        }
    }

    private func buildEjectableVolumesSection(in menu: NSMenu) {
        let volumes = VolumeMonitor.ejectableVolumes()

        if volumes.isEmpty {
            let item = NSMenuItem(title: "No ejectable volumes", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
            return
        }

        for volume in volumes {
            let item = NSMenuItem()

            let icon = NSWorkspace.shared.icon(forFile: volume.path)
            icon.size = NSSize(width: 16, height: 16)

            let view = VolumeMenuItemView(icon: icon, name: volume.name, volumeURL: volume.volumeURL, deviceType: volume.deviceType) { [weak self] in
                self?.ejectVolume(named: volume.name, at: volume.volumeURL)
            }
            item.view = view
            item.toolTip = "Click to eject \(volume.name)"

            menu.addItem(item)
        }
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

        menu.addItem(NSMenuItem(
            title: "Quit MenuBarFS",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))
    }

    // MARK: - Actions

    private func connectDrive(_ drive: NetworkDrive) {
        driveManager.mount(drive) { _ in }
    }

    private func ejectVolume(named volumeName: String, at url: URL) {
        FileManager.default.unmountVolume(
            at: url,
            options: [.allPartitionsAndEjectDisk]
        ) { error in
            DispatchQueue.main.async {
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
