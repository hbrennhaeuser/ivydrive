# Drive Availability Checks

How MenuBarFS determines whether an unconfigured network drive's host is reachable before the user attempts to mount it.

## Overview

When the menu opens, unmounted drives show a colored status dot:
- **Grey** — no checks enabled or result pending
- **Blue** — all enabled checks passed
- **Red** — at least one check failed
- **Spinner** — check in progress (first open after launch, or no cached result yet)

## Architecture

`DriveAvailabilityChecker` (singleton) runs all checks off the main thread and delivers results back on the main queue. `AppDelegate` owns a result cache and a registry of live `NetworkDriveMenuItemView` instances so results can be applied in-place without rebuilding the menu.

## Check Flow

```
menuWillOpen
  └── rebuildMenu()
  │     ├── renders menu with cached results (fast, no blocking)
  │     └── startAvailabilityCheck(for: uncached)  [drives with no cached result]
  │           └── DriveAvailabilityChecker.checkAllAsync(drives)
  │                 └── [background thread] checkAll(drives)
  │                       ├── deduplicate drives by scheme://host:port (hostGroupKey)
  │                       ├── for each unique host → hostQueue.addOperation { checkHost() }
  │                       │     Phase 1: DNS (300 ms cap)
  │                       │       - skipped if host is an IP address
  │                       │       - getaddrinfo dispatched to .utility queue + semaphore wait
  │                       │       - failure short-circuits phases 2+
  │                       │     Phase 2: reachability + port in parallel (2.0 s budget)
  │                       │       - reachability: NWPathMonitor (global, not host-specific)
  │                       │       - port: non-blocking TCP connect + poll(1 500 ms)
  │                       ├── OperationQueue cap: 6 concurrent host checks
  │                       └── batch wall-clock cap: 2.5 s (group.wait)
  │                 └── [main queue] completion callback
  │                       ├── merge results into cachedAvailability
  │                       ├── record per-drive check time in driveCheckTimes[id]
  │                       ├── call updateAvailability() on each live view (in-place dot update)
  │                       └── follow-up check for any still-uncached unmounted drives
  └── start 5 s repeating refresh timer (fires only while menu is open)
        └── refreshAvailabilityIfNeeded()
              ├── for each unmounted drive: check age against per-drive interval
              │     - problem result (any failed/timedOut check): refresh after 5 s
              │     - clean result (all passed/disabled/skipped): refresh after 30 s
              └── startAvailabilityCheck(for: stale drives)
```

## Timeouts

| Stage | Limit | Reason |
|-------|-------|--------|
| DNS (`getaddrinfo`) | 300 ms | No native timeout; dispatched async + semaphore cap |
| TCP connect (`poll`) | 1 500 ms | Non-blocking connect; `poll` returns after this delay |
| Reachability + port phase | 2 000 ms | Combined budget for Phase 2 |
| Entire batch | 2 500 ms | Wall-clock cap via `group.wait` |

## Cache and Refresh Intervals

Results are cached per drive UUID in `cachedAvailability`. Each drive also has an entry in `driveCheckTimes` recording when it was last checked.

While the menu is open a 5 s timer calls `refreshAvailabilityIfNeeded()`, which re-checks any drive whose cached result is stale:

| Result quality | Refresh interval |
| -------------- | ---------------- |
| Problem (any `failed` or `timedOut`) | **5 seconds** |
| Clean (all `passed`, `disabled`, or `skipped`) | **30 seconds** |

The cache is **merged**, not replaced: a partial-batch check never evicts results for drives not in the batch. The timer is started in `menuWillOpen` and cancelled in `menuDidClose` — no background polling occurs when the menu is closed.

## Host Deduplication

Drives sharing the same `hostGroupKey` (`scheme://host:port`) are checked once. The union of enabled checks across the group is run, and the result is fanned out to each drive — masked by that drive's individual check settings.

Example: two SMB shares on the same server each with "check port" enabled → one TCP probe, two result entries.

## In-Place Updates

The menu is **never rebuilt** during an availability check. Instead, `AppDelegate` registers each `NetworkDriveMenuItemView` in `liveAvailabilityViews[driveID]` when building the menu. The completion callback calls `updateAvailability(_:)` on each view, which mutates the `CALayer` background color and hides the spinner in place.

## Hover Panel Countdowns

The hover info panel for an unmounted drive shows two live countdowns:

- **Refresh in Xs** — time until the next scheduled availability re-check for this drive (based on result quality and last check time)
- **Autoconnect in Xs** — time until the pending autoconnect fires (if autoconnect is enabled and a connect is scheduled)

Both counts tick every second via a `.common` run loop timer while the cursor is over the drive row.

## Individual Check Flags

Each `NetworkDrive` carries three boolean flags:
- `checkDNSResolution` — Phase 1; skipped for IP hosts
- `checkHostReachability` — Phase 2 NWPathMonitor
- `checkPortAvailability` — Phase 2 TCP probe

If all three are disabled, the drive is recorded as all-`.disabled` immediately with no network I/O.

## Key Files

- `Sources/Services/DriveAvailabilityChecker.swift` — all check logic
- `Sources/AppDelegate.swift` — cache, refresh timer, `startAvailabilityCheck`, `refreshAvailabilityIfNeeded`, `liveAvailabilityViews`
- `Sources/Views/NetworkDriveMenuItemView.swift` — `updateAvailability(_:)`, spinner/dot state, hover countdown timer
- `Sources/Models/NetworkDrive.swift` — `hostGroupKey`, check flag properties
