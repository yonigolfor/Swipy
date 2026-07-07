# Swipy — Future Features Roadmap

This document tracks planned features that are not yet implemented. Each entry includes a description, UX behavior, technical notes, and an implementation difficulty rating.

---

## Offline Mode (iCloud Photos Smart Handling)

**Status:** Planned  
**Difficulty:** ⭐⭐⭐⭐☆ (Medium-Hard — 4/5)  
**Marketing angle:** "Declutter on the go — even at 35,000 feet."

---

### The Real Problem

When a user has "Optimize iPhone Storage" enabled in iCloud Photos settings, the iPhone stores only low-resolution thumbnails locally and keeps full-resolution assets in iCloud. `PHImageManager` attempts to download from iCloud on demand — so when the user is on a plane, traveling abroad without strong WiFi, or in airplane mode, photos and videos that aren't cached locally will either:
- Display as a blurry/degraded thumbnail
- Spin indefinitely waiting to download
- Fail silently and show nothing

This makes Swipy unusable for exactly the users who need it most — people traveling who want to clean up photos from their trip.

---

### Product Vision (the One-Line Summary)

> A dedicated **Airplane Mode button** in Swipy that filters the stack to show **only photos that are fully on-device**, with zero waiting, zero spinners — plus an automatic prompt to activate it whenever the app detects a poor or absent connection.

---

### UX Behavior

#### 1. Airplane Mode Button (Manual Trigger)

- A clearly visible button in the main swipe screen UI — styled as a subtle pill/toggle, consistent with the app's glassmorphic aesthetic.
- Label: ✈ **Offline Mode** (or a plane icon alone — no verbose text needed at premium quality level).
- When activated:
  - The stack immediately filters to show **only locally-available assets** (confirmed on-device via `PHAssetResource`).
  - iCloud-only assets that haven't been pre-fetched are hidden from the active stack — not deleted, not lost, just deferred.
  - A soft transition animation (crossfade or slide) signals the mode switch.
  - The button glows / changes state to indicate the mode is active.
- When deactivated (back to normal mode):
  - iCloud-only assets reappear in the stack at their original positions.
  - Pre-fetch resumes silently.

#### 2. Auto-Prompt on Poor Connectivity

- `NWPathMonitor` monitors connectivity continuously in the background.
- When the app detects no connection or a severely degraded connection (path `status == .unsatisfied` or path is `isConstrained`):
  - A non-blocking bottom sheet or pill banner slides up:
    > *"Looks like you're offline. Switch to Offline Mode to keep swiping with photos already on your device."*
    > **[Switch to Offline Mode]**  &nbsp;&nbsp;  *[Dismiss]*
  - If the user taps "Switch", Offline Mode activates instantly.
  - If dismissed, they continue normally (and will see loading delays on iCloud-only photos).
  - Never prompt more than once per session — don't nag.

#### 3. Cloud Badge on Deferred Cards

- When Offline Mode is OFF but connectivity is poor, iCloud-only cards that are deferred to the end of the stack display a small, subtle cloud icon (☁) in the top corner of the card thumbnail.
- The badge communicates: *"This photo needs a connection to load fully."*
- Style: white SF Symbol `cloud` or `icloud`, small size, `.ultraThinMaterial` background pill, low opacity — not alarming, just informative.
- When Offline Mode is ON, these cards are simply hidden from the stack (no badge needed — they're out of the way).

#### 4. Silent Pre-Fetch When on WiFi (Proactive)

- While on a strong connection (non-expensive, non-constrained), the app silently pre-fetches and caches the full-resolution versions of the next 20 assets in the stack to disk.
- This is invisible to the user — no UI, no progress indicator.
- Goal: by the time the user boards a plane, their next N photos are already available locally even if they never touched Offline Mode.
- Pre-fetch is paused immediately when:
  - Connection becomes expensive (cellular) or constrained (Low Data Mode).
  - The app moves to the background.
  - The user is actively swiping (yield to swipe performance — see Threading below).

#### 5. Graceful Degradation Tiers

| Connectivity State | Behavior |
|---|---|
| Strong WiFi | Normal + silent background pre-fetch of next 20 assets |
| Cellular (expensive) | Pre-fetch paused; `isNetworkAccessAllowed = true` for active card only |
| Low Data Mode | Pre-fetch disabled; thumbnails only for non-cached assets |
| Poor/no connection | Auto-prompt to activate Offline Mode |
| Offline Mode ON | Stack filtered to local-only assets; zero network calls |

---

### Architecture & Implementation Plan

#### Step 1 — `NetworkMonitorService.swift` (new file)

```swift
// Singleton. Publishes connectivity state.
// Uses NWPathMonitor on a dedicated background DispatchQueue.
// Results published to @MainActor via await MainActor.run — never DispatchQueue.main.async.
@MainActor
class NetworkMonitorService: ObservableObject {
    static let shared = NetworkMonitorService()
    @Published private(set) var isOnline: Bool = true
    @Published private(set) var isExpensive: Bool = false     // cellular
    @Published private(set) var isConstrained: Bool = false   // Low Data Mode
    @Published private(set) var isSatisfied: Bool = true

    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.swipy.networkmonitor", qos: .utility)

    func start() { /* monitor.start(queue: monitorQueue) + path handler */ }
}
```

#### Step 2 — Per-Asset Availability Check

```swift
// In PhotoItem.swift or PhotoLibraryService.swift — check if asset is fully on-device:
func isLocallyAvailable(_ asset: PHAsset) -> Bool {
    let resources = PHAssetResource.assetResources(for: asset)
    return resources.contains {
        ($0.value(forKey: "locallyAvailable") as? Bool) == true
    }
}

// Secondary check via image request result info:
// PHImageResultIsInCloudKey == true → asset is iCloud-only
// PHImageResultIsDegradedKey == true → only thumbnail is available
```

#### Step 3 — `PHImageRequestOptions` — iCloud-Aware

```swift
let options = PHImageRequestOptions()
// In Offline Mode: never attempt iCloud download → no stall, no spinner
options.isNetworkAccessAllowed = !isOfflineMode
options.deliveryMode = .opportunistic   // show best available immediately
options.version = .current
options.resizeMode = .fast
```

#### Step 4 — Disk Cache (`OfflineCacheService.swift`, new file)

- `FileManager`-backed cache in `Caches/OfflinePhotoCache/` (OS can purge if needed — this is correct for a cache).
- **Max size: 500 MB** — enforced on every write. If adding a new entry would exceed 500 MB, evict the oldest entries (by file creation date) until there is room.
- **Evict on swipe** — when a card is swiped (kept, deleted, or starred), its cached file is deleted immediately. No point keeping what the user has already judged.
- **Evict on Offline Mode deactivation** — optionally clear the cache when the user turns off Offline Mode to reclaim space.
- File naming: `{asset.localIdentifier}.jpg` (sanitize slashes from localIdentifier).
- Thread safety: all disk I/O on a dedicated `DispatchQueue(label:, qos: .utility)`.

```swift
class OfflineCacheService {
    static let shared = OfflineCacheService()
    private let maxCacheSize: Int = 500 * 1024 * 1024  // 500 MB
    private let ioQueue = DispatchQueue(label: "com.swipy.offlinecache", qos: .utility)

    func store(imageData: Data, for assetID: String) { ... }
    func retrieve(for assetID: String) -> UIImage? { ... }
    func evict(for assetID: String) { ... }
    func evictAll() { ... }
    private func enforceMaxSize() { /* evict oldest until under limit */ }
}
```

#### Step 5 — Background Pre-Fetch Threading

```swift
// Pre-fetch task runs at .utility (one step below .userInitiated).
// This guarantees swipe gestures (running at .userInteractive) always win CPU time.
Task.detached(priority: .utility) {
    for asset in nextTwentyAssets {
        guard !Task.isCancelled else { break }
        guard networkMonitor.isOnline && !networkMonitor.isExpensive else { break }
        // request full image → store to OfflineCacheService
        // yield between each fetch to avoid starving the main thread
        await Task.yield()
    }
}
// Cancel pre-fetch task immediately when user starts a drag gesture.
// Resume after drag ends (card settles).
```

- QoS: `.utility` for pre-fetch — never `.userInitiated` or `.userInteractive`.
- The pre-fetch task is cancelled at drag start (`onChanged`) and restarted at drag end (`onEnded`). This is the key guarantee that 60fps swipes are never affected.
- Max concurrent pre-fetches: 1 (serial, not parallel) — bandwidth should go to the active card first.

#### Step 6 — Stack Reordering (`PhotoStackViewModel`)

```swift
// Called when isOfflineMode becomes true.
// Partition in-place: local assets first, cloud-only deferred to end.
// Does NOT remove anything — just reorders. All assets remain in the queue.
func applyOfflineModeFilter() {
    let (local, cloudOnly) = photoStack.partition { isLocallyAvailable($0.asset) }
    photoStack = local + cloudOnly
    // cloudOnly items carry a flag: item.isCloudOnly = true → PhotoCardView shows cloud badge
}
```

#### Step 7 — Offline Mode Toggle State

- `@Published var isOfflineMode: Bool` on `PhotoStackViewModel`.
- Persisted via `@AppStorage("isOfflineModeEnabled")` so it survives app restart.
- When toggled ON: call `applyOfflineModeFilter()` + cancel active pre-fetch + set `isNetworkAccessAllowed = false` globally.
- When toggled OFF: restore original stack order + resume pre-fetch.

#### Step 8 — Auto-Prompt UI

- Triggered by `NetworkMonitorService.$isSatisfied` flipping to `false`.
- Shown once per app session (guard with a `hasPromptedOfflineThisSession` flag).
- Dismiss gesture or "Dismiss" button sets the flag — no repeat.
- Style: bottom-anchored sheet, `.ultraThinMaterial` background, swipe-to-dismiss, consistent with existing app modals.

---

### Files to Create / Modify

| File | Action | Notes |
|---|---|---|
| `NetworkMonitorService.swift` | **Create** | Services/ folder |
| `OfflineCacheService.swift` | **Create** | Services/ folder, 500MB cap |
| `PhotoStackViewModel.swift` | **Modify** | Add `isOfflineMode`, `applyOfflineModeFilter()`, pre-fetch task mgmt |
| `PhotoItem.swift` | **Modify** | Add `isCloudOnly: Bool` flag |
| `SwipeStackView.swift` | **Modify** | Add airplane mode button, offline prompt sheet |
| `PhotoCardView.swift` | **Modify** | Add cloud badge overlay when `item.isCloudOnly` |
| `PhotoLibraryService.swift` | **Modify** | Add `isLocallyAvailable()` helper |

---

### Implementation Difficulty Breakdown

| Sub-task | Difficulty |
|---|---|
| `NWPathMonitor` → `NetworkMonitorService` | Easy |
| Per-asset local availability check (`PHAssetResource`) | Medium |
| `OfflineCacheService` with 500MB cap + eviction | Medium |
| Background pre-fetch at `.utility` QoS + cancel-on-drag | Medium-Hard |
| Stack reordering + `isCloudOnly` flag | Medium |
| Airplane Mode button UI + active state styling | Easy |
| Auto-prompt sheet (once-per-session logic) | Easy |
| Cloud badge on `PhotoCardView` | Easy |
| Restoring stack order when Offline Mode deactivated | Medium |
| Testing: airplane mode mid-session, 500MB overflow, Low Data Mode | Hard |

**Overall: 4/5** — Individual pieces are manageable. The hard parts are (a) ensuring pre-fetch never bleeds into swipe frame time, and (b) correctly checking `PHAssetResource` availability which behaves differently across iCloud sync states. Integration testing requires a real device with iCloud Photos + Optimize Storage enabled.

---

---

## "מידע מיושן" Smart Filter (Real-World Informational Clutter)

**Status:** Planned  
**Difficulty:** ⭐⭐⭐☆☆ (Medium — 3/5)  
**Marketing angle:** "Stop hoarding photos of menus you'll never visit again."

---

### The Real Problem

Users accumulate hundreds of photos of physical documents, restaurant menus, receipts, whiteboards, and street signs — captured for immediate utility and forgotten the next day. These are not memories. They are noise. No existing filter targets them because they require pixel-level analysis (text density) rather than metadata alone.

---

### Product Vision

> A dedicated filter that surfaces only **real-world camera captures of informational content** — menus, receipts, whiteboards, signage, documents. One swipe session clears months of accidental clutter.

---

### Inclusion / Exclusion Criteria

**Included:**
- Photos of restaurant menus, store opening hours, parking zone maps, flight boards
- Photos of physical receipts, invoices, contracts, printed forms
- Photos of whiteboards, presentation slides, school blackboards
- Photos of street signs and informational signage (without scenic composition)

**Excluded (critical for false-positive prevention):**
- Any photo containing a detectable face — portraits and group shots, even with background text
- Aesthetic photos of landmarks or street scenes (high aesthetic score signals artistic intent)
- Screenshots — excluded at `PHFetchRequest` level via `mediaSubtype != .photoScreenshot`
- Art, book covers, album art — typography as design, not information

---

### Detection Pipeline (3 Signals)

All signals run on a 300×300 thumbnail via Vision framework. Signals run in parallel via `withTaskGroup`.

| Signal | Tool | Conservative Threshold | Role |
|---|---|---|---|
| Text coverage | `VNDetectTextRectanglesRequest` → covered area / total area | `> 30%` | Primary include signal |
| Face detection | `VNDetectFaceRectanglesRequest` | Any face → exclude | Hard exclude gate |
| Aesthetic score | `AestheticScoringService.cachedScore(for:)` | `≥ 7` → exclude | Soft exclude gate (optional) |

The aesthetic score gate is **optional**: if the persona is not yet ready, the filter proceeds on text + face signals alone. When the cached score is available and ≥ 7, the item is excluded to protect artistic street photography and scenic shots that happen to contain signage.

**Combined rule:** include only when `textCoverage > 30% AND noFacesDetected AND (scoreUnavailable OR score < 7)`.

---

### Architecture Notes

- **PHFetchRequest filter:** `mediaSubtype != .photoScreenshot` and `mediaType == .image` — applied before any pixel analysis.
- **Phase structure:** Phase 1 count is unavailable (no metadata signal for text). The category shows a shimmer immediately and streams results from Phase 2 only — same pattern as `blurryPhotos`.
- **Threading:** `VNDetectTextRectanglesRequest` and `VNDetectFaceRectanglesRequest` are synchronous Vision calls — must run on `DispatchQueue.global`, not `Task.detached`, to avoid cooperative thread pool blocking.
- **False-positive rate target:** < 5%. The 30% text-coverage threshold is intentionally conservative. Portraits are hard-excluded via face detection regardless of text presence.
- **`FilterCategory` addition:** `.outdatedInfo` case with `.teal` color and `doc.text.magnifyingglass` SF Symbol.

---

### Files to Create / Modify

| File | Action | Notes |
|---|---|---|
| `FilterCategory.swift` | **Modify** | Add `.outdatedInfo` case, color, icon, localized strings |
| `PhotoLibraryService.swift` | **Modify** | Add `fetchOutdatedInfoPhotos()` with PHFetchRequest filtering out screenshots |
| `PhotoStackViewModel.swift` | **Modify** | Add Phase 2 streaming for `.outdatedInfo` using VNDetectTextRectanglesRequest + VNDetectFaceRectanglesRequest |
| `SmartFiltersView.swift` | **Modify** | Add tile for new category |
| `Localizable.xcstrings` | **Modify** | Add `filter.outdated_info`, `filter.outdated_info.desc` |

---

### Implementation Difficulty Breakdown

| Sub-task | Difficulty |
|---|---|
| `FilterCategory` enum + UI tile | Easy |
| PHFetchRequest with screenshot exclusion | Easy |
| `VNDetectTextRectanglesRequest` text coverage ratio | Medium |
| `VNDetectFaceRectanglesRequest` hard-exclude gate | Easy |
| Aesthetic score optional gate integration | Easy |
| Phase 2 streaming + `withTaskGroup` parallelism | Medium |
| Threshold calibration on real photo libraries | Hard |

**Overall: 3/5** — Individual pieces are straightforward. The hard part is calibrating the 30% text-coverage threshold against real libraries with diverse photo types. A threshold too low captures street scenes; too high misses sparse receipts. Calibration requires testing on 500+ real-world photos across categories.

---

---

## TikTok-Level Image Prefetch Buffer

**Status:** Done ✅  
**Difficulty:** ⭐⭐☆☆☆ (Easy — 2/5)  
**Impact:** Eliminates all visible loading states during rapid swiping.

---

### The Real Problem

The current architecture is solid but conservatively sized. Under normal swiping (one card every 1–2 seconds) it's imperceptible. Under rapid swiping (3–5 cards in quick succession), items at stack positions 6+ are not yet in NSCache, producing a brief spinner before the card renders. The goal is to guarantee zero loading state regardless of swipe speed.

---

### What Changes

Four targeted constant changes across two files — no architectural modifications:

| Parameter | Current | Target | Rationale |
|---|---|---|---|
| `NSCache countLimit` | 6 (top-5 + undo) | 10 (top-8 + undo + safety) | Covers rapid 8-card burst; each retina card ≈ 2–3 MB → 10 cards ≈ 30 MB (negligible) |
| `precacheNextImages` depth | `prefix(5)` | `prefix(8)` | Matches the deeper NSCache; ensures `finalImageIDs` is populated for 8 cards ahead |
| `startCachingImages` hint depth | 5 items | 20 items | OS decode pipeline hint — zero memory cost in our cache; iOS pre-decodes in background |
| Early drag trigger | 80pt | 30pt | Fires ~200ms earlier per gesture; gives more runway for background loads to complete |
| Pagination watermark | 12 items | 15 items | Phase 2 streaming categories (blurry, burst) trickle items slowly — 3 extra cards of buffer covers the gap without any pixel-loading overhead (watermark controls metadata fetch only) |

---

### Memory Impact

| Scenario | NSCache footprint |
|---|---|
| Current (6 slots) | ≈ 12–18 MB |
| After change (10 slots) | ≈ 20–30 MB |
| NSCache behavior | Auto-evicts under memory pressure — no leak risk |

The increase is safe. NSCache's OS-managed eviction means the footprint drops automatically on any memory pressure event.

---

### Files to Modify

| File | Change |
|---|---|
| `PhotoLibraryService.swift` | `countLimit`: 6 → 10 |
| `PhotoStackViewModel.swift` | `precacheNextImages` prefix: 5 → 8; `startCachingImages` hint: 5 → 20; drag trigger: 80 → 30 |

---

### Implementation Difficulty Breakdown

| Sub-task | Difficulty |
|---|---|
| Constant changes in two files | Trivial |
| Verifying eviction policy still correct at depth 8 | Easy |
| Smoke-test rapid swiping on device | Easy |

**Overall: 2/5** — Pure constant tuning. Risk is near-zero because NSCache handles memory pressure automatically and the eviction logic (`evictStaleCacheEntries(keeping:)`) already operates on whatever `prefix(N)` is passed to it.

<!-- Add future features below this line in the same format -->
