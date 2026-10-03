# MenuBarFS

macOS menu bar app for managing network drives and ejectable volumes.

## Features

- Configure and connect network drives (SMB, NFS, FTP, AFP, or any URI macOS can mount, e.g. WebDAV via `https://`)
- Eject USB drives, CDs, DMGs, and network volumes from one place
- Status indicator per drive: green (mounted), blue (availability checks pass), red (a check failed), grey (no checks configured)
- Optional per-drive availability checks (DNS, network reachability, port) with automatic refresh while the menu is open
- Per-drive autoconnect on app startup and on network change
- Drives grouped by host, optional capacity bar and hover info for mounted volumes
- Notifications for autoconnect, eject, and failed eject
- Launch at login
- No dock icon - lives entirely in the menu bar

## Credentials

MenuBarFS does not store passwords. When a share requires authentication, macOS shows its native prompt and saves the credentials in the Keychain. Drive URLs are stored in plain text in the app's preferences, so URIs containing a password are rejected.

## Requirements

- macOS 14.0 (Sonoma) or later on Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`)
- Python 3.10 or later for `make dmg` only ([dmgbuild](https://github.com/dmgbuild/dmgbuild) is installed into `.venv/` automatically)

## Build

| Command        | Result                                              |
|----------------|-----------------------------------------------------|
| `make`         | Release build at `build/MenuBarFS.app`              |
| `make debug`   | Debug build                                         |
| `make run`     | Build and launch                                    |
| `make dmg`     | Disk image at `build/MenuBarFS-<version>.dmg`       |
| `make install` | Copy the app to `/Applications/`                    |
| `make clean`   | Remove `build/`                                     |

The architecture defaults to `arm64` and can be overridden with `make ARCH=x86_64`. The deployment target is read from `LSMinimumSystemVersion` in `Resources/Info.plist`.

## Releases

The `build` GitHub Actions workflow is started manually and attaches the disk image to the run as an artifact. Releases are created manually on GitHub with the disk image from that run.

## Install

Builds are ad-hoc signed and not notarized. When the app is opened from a downloaded disk image, Gatekeeper blocks it on first launch. Allow it via System Settings → Privacy & Security → Open Anyway, or remove the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/MenuBarFS.app
```

## Uninstall

1. Disable "Launch at login" in Preferences, then quit MenuBarFS.
2. Delete `/Applications/MenuBarFS.app`.
3. Remove the stored settings and drive list:

```sh
defaults delete com.hbrennhaeuser.menubarfs
```

## Documentation

- [Availability checks](docs/availability-checks.md)
- [Autoconnect](docs/autoconnect.md)

## Project Structure

```
Sources/
  main.swift                        Entry point
  AppDelegate.swift                 Status bar + menu management
  Models/
    NetworkDrive.swift              Configured drive model
    MountedVolume.swift             Mounted volume model
  Services/
    NetworkDriveManager.swift       Drive config persistence + NetFS mount
    VolumeMonitor.swift             DiskArbitration observer + volume queries
    MountTable.swift                Mounted filesystem lookup
    DriveAvailabilityChecker.swift  DNS / reachability / port checks
    AutoConnectService.swift        Startup and network-change autoconnect
    NotificationManager.swift       User notifications
  Views/
    PreferencesView.swift           SwiftUI preferences window
    DriveFormView.swift             SwiftUI add/edit drive form
    AboutView.swift                 SwiftUI about window
    DriveInfoPanel.swift            Hover info panel
    NetworkDriveMenuItemView.swift  Network drive menu row
    VolumeMenuItemView.swift        Mounted volume menu row
Resources/
  Info.plist                        App metadata (LSUIElement, bundle ID)
  AppIcon.icns                      App icon
```

## License

Licensed under the GNU General Public License v3.0 only (GPL-3.0-only). See [LICENSE](LICENSE).
