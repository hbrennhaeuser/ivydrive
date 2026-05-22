# Autoconnect

How MenuBarFS automatically mounts network drives without user interaction.

## Overview

Each drive has an `autoConnect` master toggle plus two trigger flags. When a trigger fires, unmounted drives with matching flags are availability-checked (if checks are configured) and mounted silently — no Finder window, no credential prompt.

## Per-Drive Settings

| Field | Type | Default | Meaning |
|-------|------|---------|---------|
| `autoConnect` | Bool | false | Master switch; disabling it clears both trigger flags |
| `autoConnectOnStartup` | Bool | false | Mount on app launch (30 s delay) |
| `autoConnectOnNetworkChange` | Bool | false | Mount when network path changes to satisfied (10 s delay) |

All fields use `decodeIfPresent` with `false` defaults for backward compatibility with drives saved before this feature existed.

## Triggers

### App Startup
Fires once, 30 seconds after `applicationDidFinishLaunching`. The delay lets the network stack and Keychain settle before mount attempts.

### Network Change
`AutoConnectService` owns a single `NWPathMonitor` that runs for the lifetime of the app. The handler fires whenever the network path changes. A trigger is scheduled when:
- new path status is `.satisfied`, AND
- the new path differs from the previous path (`NWPath` is `Equatable`)

The second condition means WiFi-only → WiFi+Ethernet (satisfied → satisfied, different interfaces) also triggers a reconnect, not just offline → online transitions. The initial path report on startup is intentionally skipped (`previousPath == nil` guard) — the startup trigger covers that case.

Delay: **10 seconds**, debounced.

## Debounce

Both triggers share a single `DispatchWorkItem` (`pendingWork`). Each call to `schedule(delay:trigger:)` cancels the pending item and schedules a new one. If multiple triggers fire in quick succession (e.g. network change fires during the 30 s startup window), only the most recent one executes.

## Mount Flow

```
trigger fires (startup or network change)
  └── AutoConnectService.runAutoConnect(trigger:)
        ├── filter drives: autoConnect && triggerFlag && !isMounted && !suppressed
        ├── drives with no checks enabled → mountSilently() immediately
        └── drives with checks enabled → DriveAvailabilityChecker.checkAllAsync()
              └── [completion] for each drive where result.dotIsTeal && !isMounted
                    └── mountSilently()
                          └── NetFSMountURLSync (background thread, no interactive fallback)
                                ├── success → NotificationManager.showConnected()
                                └── failure → silent, no alert
```

`isMounted` is re-checked just before mounting (after the async availability check) to avoid double-mounting if the drive came up via another path in the interim.

## Silent Mount

`NetworkDriveManager.mountSilently(_:completion:)` calls `NetFSMountURLSync` and returns `.mounted` or `.failed`. Unlike the interactive `mount(_:completion:)`, it never calls `NSWorkspace.shared.open(url)` — so no Finder window or credential dialog appears on failure. Drives with credentials not stored in Keychain will silently fail autoconnect.

## Eject Suppression

When the user ejects a drive from within the app, `AppDelegate.ejectVolume` looks up the matching `NetworkDrive` and calls `AutoConnectService.suppressAutoConnect(for: driveID)`. The drive is added to `suppressedIDs` and removed after **5 minutes**. This prevents a pending network-change trigger from immediately reconnecting a drive the user just intentionally ejected.

Ejects initiated from Finder are not detectable and are not suppressed.

## Key Files

- `Sources/Services/AutoConnectService.swift` — trigger logic, NWPathMonitor, debounce, mount orchestration
- `Sources/Services/NetworkDriveManager.swift` — `mountSilently(_:completion:)`
- `Sources/Models/NetworkDrive.swift` — `autoConnect`, `autoConnectOnStartup`, `autoConnectOnNetworkChange` fields
- `Sources/AppDelegate.swift` — `autoConnectService` wiring, eject suppression call
- `Sources/Services/NotificationManager.swift` — `showConnected(_:)`
