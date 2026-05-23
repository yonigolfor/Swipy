# Offline Mode — Architecture & Prompt Logic

## What Offline Mode Does

When active, the stack is filtered to **locally-available assets only** — photos and videos that are physically on-device (not waiting in iCloud). No network traffic is initiated for image loading.

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

## Key Files

| File | Role |
|---|---|
| `NetworkMonitorService.swift` | `NWPathMonitor` wrapper, publishes `isOnline`, `isExpensive`, `isConstrained` |
| `PhotoStackViewModel.swift` | Observers, `recordNetworkFailure()`, `activateOfflineMode()`, `deactivateOfflineMode()` |
| `PhotoLibraryService.swift` | `loadImage()` — iCloud timeout + fallback + quality upgrade callback |
| `SwipeStackView.swift` | `offlinePromptBanner` — renders copy based on `offlinePromptReason` |
| `OfflineCacheService.swift` | Disk cache (500 MB, LRU) used by background prefetch for offline availability |
