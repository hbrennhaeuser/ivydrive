import Cocoa
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()
    let driveManager = NetworkDriveManager()
    let volumeMonitor = VolumeMonitor()

    private var preferencesWindow: NSWindow?
    private var aboutWindow: NSWindow?

    // MARK: - App Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupVolumeMonitor()
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

    private func setupVolumeMonitor() {
        volumeMonitor.onVolumesChanged = { [weak self] in
            _ = self
        }
        volumeMonitor.start()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        menu.removeAllItems()
        buildNetworkDrivesSection(in: menu)
        menu.addItem(.separator())
        buildEjectableVolumesSection(in: menu)
        menu.addItem(.separator())
        buildAppSection(in: menu)
    }

    // MARK: - Menu Sections

    private func buildNetworkDrivesSection(in menu: NSMenu) {
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
                name: drive.displayName,
                connected: mounted
            ) { [weak self] in
                self?.driveManager.mount(drive)
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

            let view = VolumeMenuItemView(icon: icon, name: volume.name) { [weak self] in
                self?.ejectVolume(at: volume.volumeURL)
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

    private func ejectVolume(at url: URL) {
        FileManager.default.unmountVolume(
            at: url,
            options: [.allPartitionsAndEjectDisk]
        ) { error in
            guard let error else { return }
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Eject Failed"
                alert.informativeText = error.localizedDescription
                alert.alertStyle = .warning
                alert.runModal()
            }
        }
    }

    @objc private func showPreferences() {
        if preferencesWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 400),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "MenuBarFS Preferences"
            window.contentView = NSHostingView(rootView: PreferencesView(manager: driveManager))
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 400, height: 300)
            preferencesWindow = window
        }
        preferencesWindow?.center()
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showAbout() {
        if aboutWindow == nil {
            let window = NSWindow(
                contentRect: .zero,
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "About MenuBarFS"
            window.contentView = NSHostingView(rootView: AboutView())
            window.isReleasedWhenClosed = false
            aboutWindow = window
        }
        aboutWindow?.center()
        aboutWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

}
