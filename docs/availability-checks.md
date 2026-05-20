# Drive Availability Checks

How MenuBarFS determines whether an unconfigured network drive's host is reachable before the user attempts to mount it.

## Overview

When the menu opens, unmounted drives show a colored status dot:
- **Grey** — no checks enabled or result pending
- **Blue** — all enabled checks passed
- **Red** — at least one check failed
- **Spinner** — check in progress (first open after launch, or cache expired)

## Architecture

`DriveAvailabilityChecker` (singleton) runs all checks off the main thread and delivers results back on the main queue. `AppDelegate` owns a result cache and a registry of live `NetworkDriveMenuItemView` instances so results can be applied in-place without rebuilding the menu.

## Check Flow

```
menuWillOpen
  └── rebuildMenu()
        ├── renders menu with cached results (fast, no blocking)
        └── startAvailabilityCheck(for:)  [if cache miss or TTL expired]
              └── DriveAvailabilityChecker.checkAllAsync(drives)
                    └── [background thread] checkAll(drives)
                          ├── deduplicate drives by scheme://host:port (hostGroupKey)
                          ├── for each unique host → hostQueue.addOperation { checkHost() }
                          │     Phase 1: DNS (200 ms cap)
                          │       - skipped if host is an IP address
                          │       - getaddrinfo dispatched to .utility queue + semaphore wait
                          │       - failure short-circuits phases 2+
                          │     Phase 2: reachability + port in parallel (0.8 s budget)
                          │       - reachability: NWPathMonitor (global, not host-specific)
                          │       - port: non-blocking TCP connect + poll(500 ms)
                          ├── OperationQueue cap: 6 concurrent host checks
                          └── batch wall-clock cap: 1.0 s (group.wait)
                    └── [main queue] completion callback
                          ├── merge results into cachedAvailability
                          ├── record lastCheckTime
                          ├── call updateAvailability() on each live view (in-place dot update)
                          └── follow-up check for any uncached unmounted drives
```

## Timeouts

| Stage | Limit | Reason |
|-------|-------|--------|
| DNS (`getaddrinfo`) | 200 ms | No native timeout; dispatched async + semaphore cap |
| TCP connect (`poll`) | 500 ms | Non-blocking connect; `poll` returns after this delay |
| Reachability + port phase | 800 ms | Combined budget for Phase 2 |
| Entire batch | 1 000 ms | Wall-clock cap via `group.wait` |

## Cache

- TTL: **60 seconds**. On `menuWillOpen`, if all unmounted drives have a cached result and the last check was under 60 s ago, no network I/O is issued and the menu renders instantly.
- Cache is **merged**, not replaced: a new batch for a subset of drives doesn't evict results for drives not in the batch.
- Cache is **keyed by drive UUID**, not by host — individual drive check flags are respected.

## Host Deduplication

Drives sharing the same `hostGroupKey` (`scheme://host:port`) are checked once. The union of enabled checks across the group is run, and the result is fanned out to each drive — masked by that drive's individual check settings.

Example: two SMB shares on the same server each with "check port" enabled → one TCP probe, two result entries.

## In-Place Updates

The menu is **never rebuilt** during an availability check. Instead, `AppDelegate` registers each `NetworkDriveMenuItemView` in `liveAvailabilityViews[driveID]` when building the menu. The completion callback calls `updateAvailability(_:)` on each view, which mutates the `CALayer` background color and hides the spinner in place.

## Individual Check Flags

Each `NetworkDrive` carries three boolean flags:
- `checkDNSResolution` — Phase 1; skipped for IP hosts
- `checkHostReachability` — Phase 2 NWPathMonitor
- `checkPortAvailability` — Phase 2 TCP probe

If all three are disabled, the drive is recorded as all-`.disabled` immediately with no network I/O.

## Key Files

- `Sources/Services/DriveAvailabilityChecker.swift` — all check logic
- `Sources/AppDelegate.swift` — cache, TTL, `startAvailabilityCheck`, `liveAvailabilityViews`
- `Sources/Views/NetworkDriveMenuItemView.swift` — `updateAvailability(_:)`, spinner/dot state
- `Sources/Models/NetworkDrive.swift` — `hostGroupKey`, check flag properties
