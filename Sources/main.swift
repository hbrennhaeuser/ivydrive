import Cocoa

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

SettingsMigration.importLegacySettingsIfNeeded()

let delegate = AppDelegate()
app.delegate = delegate
app.run()
