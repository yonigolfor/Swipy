# Offline Mode — Architecture & Prompt Logic

## What Offline Mode Does

When active, the stack is filtered to **locally-available assets only** — photos and videos that are physically on-device (not waiting in iCloud). No network traffic is initiated for any media loading operation. This guarantee holds regardless of whether offline mode was triggered by a real network loss or manually by the user on a slow connection.

Activated via:
- User tapping "Switch" in the offline prompt banner
- User tapping the airplane FAB in `SwipeStackView`

Deactivated via:
- Tapping the X in the offline badge
- Tapping the airplane FAB again

Offline mode is **session-scoped** — it does not persist across app launches. It's a "boarding a flight now" action, not a persistent setting.

---

## When the Prompt Appears

The banner (`showOfflinePrompt = true`) is triggered by three independent conditions. Each has its own copy and icon.

### 1. Complete offline (`reason = .offline`)

**Trigger:** `NetworkMonitorService.$isOnline` transitions from `true` → `false`

**Observer:** `startNetworkObserver()` → `networkObserverTask` in `PhotoStackViewModel`

**Conditions to show:**
- `!isOnline`
- `!isOfflineMode` (already in offline mode → no need)
- `!hasPromptedOfflineThisSession` (once per session)

**Banner copy:**
- Icon: `wifi.slash`
- Title: "You're offline"
- Subtitle: "Switch to swipe only locally stored photos"

---

### 2. Low Data Mode (`reason = .constrained`)

**Trigger:** `NetworkMonitorService.$isConstrained` transitions to `true`

**Observer:** `startNetworkObserver()` → `networkConstrainedObserverTask` in `PhotoStackViewModel`

**Conditions to show:**
- `isConstrained == true`
- `!isOfflineMode`
- `!hasPromptedOfflineThisSession` (shared flag with reason `.offline`)

**Banner copy:**
- Icon: `wifi.exclamationmark`
- Title: "Low Data Mode is on"
- Subtitle: "Switch to Offline Mode to avoid using data"

---

### 3. Lie-fi / Slow network (`reason = .slowNetwork`)

**Trigger:** 2 iCloud image timeouts within a 60-second window

**Observer:** `recordNetworkFailure()` called from `precacheNextImages()` and `prepareUpcomingCards()` via `onSlowNetwork` callback in `PhotoLibraryService.loadImage()`

**Conditions to show:**
- `networkFailureCount >= 2`
- Last failure within 60 seconds of the current one
- `!isOfflineMode`
- `!hasPromptedSlowNetworkThisSession` (independent flag — not shared with reason `.offline`)

**Banner copy:**
- Icon: `wifi.exclamationmark`
- Title: "Connection seems slow"
- Subtitle: "Switch to Offline Mode for a smoother experience ⚡️"

---

## Prompt Lifecycle

```
trigger fires
    └─ showOfflinePrompt = true (animated spring)
    └─ offlinePromptReason = .<reason>
    └─ Task: sleep 8s → showOfflinePrompt = false (animated easeOut)

User taps "Switch"
    └─ showOfflinePrompt = false
    └─ performOfflineTransition { activateOfflineMode() }

User taps X
    └─ showOfflinePrompt = false
    (reason flags unchanged — prompt won't reappear this session)
```

Auto-dismiss fires after **8 seconds** if the user ignores the banner.

---

## Session Flags

| Flag | Resets | Controls |
|---|---|---|
| `hasPromptedOfflineThisSession` | Never (session-scoped) | reasons `.offline` and `.constrained` |
| `hasPromptedSlowNetworkThisSession` | Never (session-scoped) | reason `.slowNetwork` |
| `networkFailureCount` | On `activateOfflineMode()` / `deactivateOfflineMode()`, or when >60s pass between failures | Lie-fi threshold counter |

---

## iCloud Timeout & Quality Upgrade

`PhotoLibraryService.loadImage()` applies a **2-second timeout** for foreground card loads (not background prefetch, not offline mode).

```
loadImage() called (highQualityFormat, isNetworkAccessAllowed = true)
    │
    ├─ image arrives within 2s
    │       └─ completion(fullQualityImage)   ← single call
    │
    └─ 2s elapse with no response
            ├─ onSlowNetwork() fired          ← increments networkFailureCount
            ├─ fastFormat local fallback delivered immediately
            │       └─ completion(degradedImage)   ← first call
            │
            └─ original iCloud request continues (NOT cancelled)
                    └─ eventually: completion(fullQualityImage)   ← second call (upgrade)
```

**Why the original request is not cancelled:** Cancelling it would leave the card permanently blurry. By letting it continue, the card silently upgrades to full quality when iCloud responds — even minutes later.

### Quality upgrade in the ViewModel

`precacheNextImages()` and `prepareUpcomingCards()` handle the double completion:

```swift
imageCache.setObject(fullQualityImage, forKey: key, cost: ...)
loadedImageIDs.remove(item.id)   // toggle forces SwiftUI re-render
loadedImageIDs.insert(item.id)   // card re-reads from NSCache → full quality
```

The `remove` + `insert` toggle on `@Published var loadedImageIDs` causes SwiftUI to re-render the card and pick up the better image already stored in `NSCache`.

---

## Network Access Enforcement in Offline Mode

The "no network in offline mode" guarantee is enforced at four independent layers:

| Layer | Mechanism |
|---|---|
| **`loadImage()`** | `options.isNetworkAccessAllowed = !isOfflineMode`; `deliveryMode = .highQualityFormat` always. In offline mode, checks `PHImageResultIsDegradedKey` — returns `nil` for any degraded proxy so blurry stand-ins are never shown. |
| **`startCaching()`** | Explicit `PHImageRequestOptions` with `isNetworkAccessAllowed = !isOfflineMode` — replaces previous `options: nil` which defaulted to network allowed |
| **`VideoPlayerPool.load()`** | `options.isNetworkAccessAllowed = !PhotoLibraryService.shared.isOfflineMode` — prevents iCloud video requests from hanging indefinitely in airplane mode |
| **Background prefetch** | `startBackgroundPrefetch()` guard: `network.isOnline && !network.isExpensive && !network.isConstrained` — never runs while offline |

The `startCaching()` and `VideoPlayerPool` fixes are what ensure snoozed items flushed via `flushSnoozedItemsNow()` load cleanly: the items have already passed the `isLocallyAvailable` / `isCached` filter, and the media pipeline now confirms it will never reach out to iCloud.

## Background Prefetch Guards

`startBackgroundPrefetch()` only runs when all three conditions are met:

```swift
guard network.isOnline && !network.isExpensive && !network.isConstrained else { return }
```

- Paused on cellular (`isExpensive`)
- Paused on Low Data Mode (`isConstrained`)
- Paused when offline
- Cancelled on drag start (`cancelPrefetch()`), resumed on drag end (`resumePrefetch()`)

---

## NetworkMonitorService Properties

Sourced from `NWPathMonitor` in `NetworkMonitorService.swift`:

| Property | Type | Meaning |
|---|---|---|
| `isOnline` | `Bool` | `path.status == .satisfied` |
| `isExpensive` | `Bool` | Cellular / hotspot connection |
| `isConstrained` | `Bool` | Low Data Mode enabled in Settings |

All three are `@Published` and observed via async `for await` streams on `@MainActor`.

---

## Scan Engine — `scanLocalUniverse()`

All photo loading in offline mode goes through `scanLocalUniverse()` in `PhotoStackViewModel`. It never fetches from iCloud — it only reads `PHAsset` metadata and an in-memory snapshot of the `OfflineCacheService` disk index.

### How it decides "locally available"

```swift
// Built once before the scan loop — single directory listing, no per-item I/O:
let cachedIDs = diskCache.cachedAssetIDSet()   // Set<String> of sanitized asset IDs

// Inside Task.detached, per asset — O(1) in-memory lookup:
let sanitizedID = asset.localIdentifier.replacingOccurrences(of: "/", with: "_")
let isLocal = service.isLocallyAvailable(asset) || cachedIDs.contains(sanitizedID)
```

**Why not `diskCache.retrieve()` per asset:** the previous implementation called `Data(contentsOf:)` for every non-local asset — a failed filesystem syscall for each. On a 20k all-iCloud library this totalled ~40 seconds. The `cachedAssetIDSet()` approach pays one `contentsOfDirectory` call upfront, then every lookup is a hash-set `contains` with no disk I/O.

**Sanitization contract:** `cachedAssetIDSet()` returns filenames stripped of their `.jpg` extension, which is exactly `assetID.replacingOccurrences(of: "/", with: "_")` — the same transform used in `fileURL(for:)`. Both sides must use this form; the comment in `scanLocalUniverse` makes this explicit.

**Memory:** the `Set<String>` lives only for the duration of the scan (`let` local in `scanLocalUniverse`). It is captured by copy-on-write reference inside `Task.detached` closures — no copies are made as long as it is never mutated (it isn't). When `scanLocalUniverse` returns the Set is freed.

### Iteration

Scans `PHFetchResult` in batches of 150, starting from `offlineFetchCursor`. Each batch runs in a `Task.detached` (off main thread); results are streamed back to `photoStack` on MainActor. The function owns the `isScanning` flag via `defer { isScanning = false }` — only one scan can run at a time.

```
offlineFetchCursor = 0
while photoStack.count < targetCount:
    batch = Task.detached { check assets [cursor..<cursor+150] }
    if batch not empty → photoStack.append, isLoading = false (first batch only)
    cursor += 150
    if cursor >= total → break  ← full library scanned, nothing left
```

### Termination guards

| Condition | Effect |
|---|---|
| `!isOfflineMode` | User exited offline mid-scan → break immediately |
| `totalScanned >= total` | Full library visited, no more assets → break |
| `offlineFetchCursor >= total` (no wrap) | Cursor past end → break |
| `guard !isScanning` at entry | Concurrent call blocked → `isLoading = false` and return |

---

## UX States in Offline Mode

`SwipeStackView` renders one of four states depending on `isOfflineMode`, `isScanning`, `isLoading`, `photoStack`, and `offlineFoundNoLocalItems`:

| Condition | What the user sees |
|---|---|
| `isOfflineMode && isScanning && photoStack.isEmpty` | **Scanning state** — airplane icon + "Searching Your Device" + ProgressView |
| `isLoading` (generic) | Standard spinner + "loading.scanning" label |
| `!isLoading && photoStack.isEmpty && !offlineFoundNoLocalItems` | **VictoryView (offline done)** — airplane icon + `victory.title_offline` — user swiped all local photos |
| `!isLoading && photoStack.isEmpty && offlineFoundNoLocalItems` | **VictoryView (offline empty)** — `icloud.slash` icon + `victory.title_offline_empty` — no locally-stored photos exist |
| `photoStack.count > 0` | Card stack |

`offlineFoundNoLocalItems` is set in `activateOfflineMode()` after `scanLocalUniverse` returns:
```swift
offlineFoundNoLocalItems = photoStack.isEmpty
```
Reset to `false` in `deactivateOfflineMode()`.

### Transition animation

`performOfflineTransition(deactivating:)` manages the fly-out/land-in animation for both activation and deactivation.

**Activation path (`deactivating: false`, default):**
- `awaitingOfflineLanding = true` is set **synchronously** at the top of the function (before any async work) — this prevents the race condition where a fast-returning `scanLocalUniverse` (blocked by the `guard !isScanning` check) could flip `isLoading` before the flag was set, causing it to be stuck `true` permanently.
- Cards fly out, then spring back immediately — the user sees the scanning state during the scan.
- `onChange(of: viewModel.isLoading)` resets `awaitingOfflineLanding = false` when the scan completes.

**Deactivation path (`deactivating: true`):**
- If `awaitingOfflineLanding` is already `true` (i.e. an activation scan is in progress), the function **bypasses the guard** — it resets the flag and calls `deactivateOfflineMode()` immediately, without a fly-out animation (the cards are already in position during the scan).
- `deactivateOfflineMode()` sets `isOfflineMode = false`, which causes `scanLocalUniverse` to exit its loop at `guard isOfflineMode else { break }` — no explicit Task cancellation needed.
- If `awaitingOfflineLanding` is `false` (normal deactivation), the full fly-out animation runs as usual.

**On deactivation, the stack always does a fresh load** (`loadPhotos(filter: .all)`) — identical to first app launch. No snapshot is restored. This avoids a class of bugs where the pre-offline snapshot was captured while shuffle mode was active, landing the user back in a shuffle-ordered deck with shuffle visually off. A clean load is the most predictable outcome regardless of what state the user was in before going offline.

---

## Pagination in Offline Mode

Pagination is **proactive** — it fires before the stack is empty.

- **Watermark:** `lowWatermark = 12`. Every swipe calls `loadNextPageIfNeeded()`. When `photoStack.count <= 12`, a new `scanLocalUniverse(targetCount: photoStack.count + 30)` starts in the background.
- **Guard:** pagination does not fire when `photoStack.isEmpty` (the scan was already triggered at count = 1).
- **Result:** if the scan finds more local photos before the user swipes the last card, the stack refills silently. If the user swipes everything before the scan completes, the scanning state appears briefly, then either cards or VictoryView.

```
photoStack.count drops to 12
    └─ scanLocalUniverse(targetCount: 42) starts in background
        ├─ finds photos → photoStack grows, no visible interruption
        └─ finds nothing → when user hits 0: scanning state → VictoryView
```

---

## Key Published Properties (ViewModel)

| Property | Type | Meaning |
|---|---|---|
| `isOfflineMode` | `Bool` | Whether offline mode is active |
| `isScanning` | `Bool` | Whether `scanLocalUniverse` is currently running |
| `isLoading` | `Bool` | Generic loading flag; drives `onChange` landing animation |
| `offlineFoundNoLocalItems` | `Bool` | Set after scan completes with zero results — no locally-stored photos exist |

## Key Files

| File | Role |
|---|---|
| `NetworkMonitorService.swift` | `NWPathMonitor` wrapper, publishes `isOnline`, `isExpensive`, `isConstrained` |
| `PhotoStackViewModel.swift` | Observers, `recordNetworkFailure()`, `activateOfflineMode()`, `deactivateOfflineMode()`, `offlineFoundNoLocalItems` |
| `PhotoLibraryService.swift` | `loadImage()` — iCloud timeout + fallback + quality upgrade callback |
| `SwipeStackView.swift` | `performOfflineTransition(deactivating:)`, `offlinePromptBanner`, `offlineBadge`, `offlineFAB` |
| `VictoryView.swift` | Empty state for offline done vs. offline empty (`offlineFoundNoLocalItems`) |
| `OfflineCacheService.swift` | Disk cache (500 MB, LRU) used by background prefetch; `cachedAssetIDSet()` for scan-time lookups; `isCached()` for lightweight existence checks (snooze filter) |
