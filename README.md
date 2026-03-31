# MenuBarFS

macOS menu bar app for managing network drives and ejectable volumes.

## Features

- Configure and connect network drives (SMB, NFS, AFP, WebDAV)
- Eject USB drives, CDs, DMGs, and network volumes from one place
- Green/red status indicators for drive connectivity
- Keychain-stored credentials
- No dock icon - lives entirely in the menu bar

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode Command Line Tools (`xcode-select --install`)

## Build

```sh
make
```

## Run

```sh
make run
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
    KeychainHelper.swift            Credential storage via Security framework
  Views/
    PreferencesView.swift           SwiftUI preferences window
    DriveFormView.swift             SwiftUI add/edit drive form
    AboutView.swift                 SwiftUI about window
Resources/
  Info.plist                        App metadata (LSUIElement, bundle ID)
```

## License

MIT
