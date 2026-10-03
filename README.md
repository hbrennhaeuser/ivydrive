# MenuBarFS

macOS menu bar app for managing network drives and ejectable volumes.

## Features

- Configure and connect network drives (SMB, NFS, AFP, WebDAV)
- Eject USB drives, CDs, DMGs, and network volumes from one place
- Green/red status indicators for drive connectivity
- Use native macOS authentication prompts for network drive credentials
- No dock icon - lives entirely in the menu bar

## Requirements

- macOS 14.0 (Sonoma) or later on Apple Silicon
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```sh
make
```

## Debug Build

```sh
make debug
```

## Install

```sh
make install
```
Copies `MenuBarFS.app` to `/Applications/`.

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
  Views/
    PreferencesView.swift           SwiftUI preferences window
    DriveFormView.swift             SwiftUI add/edit drive form
    AboutView.swift                 SwiftUI about window
Resources/
  Info.plist                        App metadata (LSUIElement, bundle ID)
```

## License

GNU General Public License v3.0
