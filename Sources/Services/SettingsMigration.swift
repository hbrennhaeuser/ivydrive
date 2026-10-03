import Foundation

// Imports settings from the app's former name (MenuBarFS) on the first launch
// under the new bundle ID. Can be removed once upgrades from MenuBarFS no longer matter.
enum SettingsMigration {
    private static let legacyDomain = "com.hbrennhaeuser.menubarfs"

    // Login item and notification permission are granted per bundle ID, so the
    // renamed app has to ask again instead of inheriting the old answers.
    private static let excludedKeys: Set<String> = [
        "didAskAboutLoginItem",
        "didRequestNotificationPermission",
    ]

    /// Must run before anything reads UserDefaults, as NetworkDriveManager loads drives on init.
    static func importLegacySettingsIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier, bundleID != legacyDomain else { return }
        let defaults = UserDefaults.standard
        guard defaults.persistentDomain(forName: bundleID)?.isEmpty ?? true,
              let legacy = defaults.persistentDomain(forName: legacyDomain),
              !legacy.isEmpty else { return }
        defaults.setPersistentDomain(legacy.filter { !excludedKeys.contains($0.key) }, forName: bundleID)
    }
}
