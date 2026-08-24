# Senior iOS Product Engineer — Manifest

**Role:** Senior iOS Product Engineer building SwiftUI apps at Apple Premium UX quality. The guiding principles are absolute smoothness (120Hz), compact code, and zero reinventing the wheel.

## Iron Principles (apply before writing a single line of code)

**Native First — Do Not Over-Engineer:**
Before reaching for complex logic, manual calculations, GeometryReader, custom frames, or Safe Area manipulations — stop and ask: "How did Apple implement this in their own apps? Which built-in SwiftUI component or modifier gives me this out of the box?"

**Leverage OS Mechanisms:**
Always prefer simple composition of system components (`NavigationStack`, `.scaledToFill`, `.sensoryFeedback`, built-in Layout Protocols) over third-party solutions or complex imperative code. OS code is always more efficient, better memory-managed, and future-proof against iOS updates.

**Measure Before Optimizing (YAGNI):**
Do not add caching layers or complex optimizations (e.g. manual `NSCache` where the OS already manages a cache) unless a Profiler has proven a real need. Clean, simple code is fast code.

For every new task, ensure the proposed solution rests on these principles and presents the shortest, most elegant, most native path.

---

# Swipy — Developer Guide

## What This App Is

**Swipy** is a native iOS photo/video management app with the tagline *"Declutter your memories."* It presents the user's photo library as a swipe-based card stack (Tinder-style). Swipe right = keep, swipe left = delete (moves to Review Bin), swipe up = snooze ("Later" — defers the decision, re-injects into the stack after N swipes). The app also auto-identifies junk photos (blurry, screenshots, large videos, burst duplicates, screen recordings) and surfaces them via Smart Filters. Items accumulate in a Review Bin before permanent deletion, giving users an undo safety net.

**App Icon:** Blue gradient background, white "S" letter.

---

## Architecture

**Pattern:** MVVM with reactive `@Published` properties. No external dependencies — pure Apple frameworks only.

```
PHPhotoLibrary
    └─ PhotoLibraryService         # fetches, filters, counts assets
         └─ PhotoStackViewModel    # @MainActor, single source of truth
              ├─ photoStack        # @Published [PhotoItem]
              ├─ reviewBin         # @Published [PhotoItem]
              ├─ loadedImageIDs    # @Published Set<String> — triggers SwiftUI re-render when image ready
              ├─ loadedScoreIDs    # @Published Set<String> — triggers badge render when score ready
              ├─ finalImageIDs     # @Published Set<String> — signals delivery complete (no more callbacks)
              ├─ AestheticScoringService     # singleton — persona + score cache
              └─ VideoPlayerPool   # singleton, max 3 AVPlayers

PhotoLibraryService (service-owned):
              ├─ NSCache<NSString, UIImage>  # 10 images online / 30 offline, OS-managed eviction (retina-pixel dimensions)
              └─ requestCardImage()  # .opportunistic online / .fastFormat offline (always isDegraded=false)
```

**State flows down, events flow up** through the ViewModel. Views only read `@EnvironmentObject var vm: PhotoStackViewModel` — they never touch services directly.

**Threading rules:**
- `PhotoStackViewModel` is `@MainActor` — all `@Published` mutations happen on main thread.
- Heavy work (blur detection, burst analysis, category counting) runs in `Task.detached(priority: .userInitiated)` or `withTaskGroup`, then publishes to main.
- Use `await MainActor.run { }` when pushing results from background tasks to the ViewModel.
- **Exception — use `DispatchQueue.global` (not `Task.detached`) for:** `PHImageManager.requestImage(isSynchronous:true)` and `VNClassifyImageRequest.perform`. Both are synchronous blocking calls that deadlock the Swift cooperative thread pool. Bridge with `withCheckedContinuation` or `DispatchQueue.global(qos:).async` + `DispatchQueue.main.async` for the result.

---

## File Structure

```
Swipy/
├── SwipyApp.swift              # Entry point + AppDelegate
├── ContentView.swift           # Root: onboarding gate → 3-tab layout
├── BlurDetector.swift          # CIEdges variance on 200×200 thumb (CILaplacian is macOS-only)
├── BurstAnalyzer.swift         # Groups by burstIdentifier OR (gap ≤30s AND VNFeaturePrint similarity < 0.85); chain comparison; min 5 items
│
├── Models/
│   ├── PhotoItem.swift         # PHAsset wrapper + metadata cache
│   ├── FilterCategory.swift    # Enum: all, screenshots, largeVideos, blurryPhotos, burstPhotos, screenRecordings
│   └── SwipeAction.swift       # Enum: keep, delete, snooze, undo
│
├── ViewModels/
│   ├── PhotoStackViewModel.swift   # ~765 lines — main state container
│   └── ReviewBinViewModel.swift    # Review Bin screen state
│
├── Views/
│   ├── Main/
│   │   ├── SwipeStackView.swift    # Screen chrome: SessionSavingsBar, FAB row, badges, paywall/share sheets
│   │   ├── CardStackView.swift     # 3-card Z-stack + drag/pinch gesture — isolated for perf, see Performance Rules
│   │   ├── PhotoCardView.swift     # Image or video card (mute, progress)
│   │   ├── SplashScreenView.swift  # Launch + onboarding router
│   │   └── OnboardingView.swift    # 5-step onboarding
│   ├── Filters/
│   │   └── SmartFiltersView.swift  # 6 categories + 2-phase counts
│   ├── ReviewBin/
│   │   ├── ReviewBinView.swift     # 3-column grid + FullScreenMediaView (detail viewer, same file)
│   │   └── ReviewGridItemView.swift
│   ├── Paywall/
│   │   └── PaywallView.swift       # 3-tier pricing (Monthly/Yearly/Lifetime), gold-glow selection, dynamic CTA
│   └── Components/
│       ├── SessionSavingsBarView.swift # Gamified top bar: MB progress + lava-star + GB milestone celebration
│       ├── LifetimeSavingsView.swift
│       ├── SwipeIndicator.swift
│       ├── VictoryView.swift           # Empty state celebration
│       ├── TrashCelebrationView.swift
│       ├── ParticleExplosionView.swift
│       ├── EmptyStateView.swift
│       ├── VideoProgressBar.swift
│       ├── ShareHUDView.swift          # Floating progress HUD shown during share (hosted in ShareHUDManager's UIWindow)
│       └── AnalyticsDebugView.swift    # DEBUG-only inspector for AnalyticsService's local event counters
│
├── Services/
│   ├── PhotoLibraryService.swift   # PHPhotoLibrary access + pagination
│   ├── AestheticScoringService.swift # Builds UserAestheticPersona from Favorites; scores cards 1–10
│   ├── BlurBurstCacheService.swift # Disk-backed verdict + feature-print cache for Blurry/Burst Smart Filters (2 debounced JSON stores)
│   ├── BlurBurstScanEngine.swift   # Nonisolated, bounded-concurrency (6) blur scanner; cache-first
│   ├── PersistenceService.swift    # UserDefaults (kept IDs, bin IDs, space saved)
│   ├── DailyLimitService.swift     # 120 free swipes/day + share bonus; gates PremiumManager paywall trigger
│   ├── PremiumManager.swift        # StoreKit 2 — PremiumTier (monthly/yearly/lifetime), entitlement status
│   ├── HapticService.swift         # UIImpactFeedbackGenerator wrapper
│   ├── AudioSessionManager.swift   # AVAudioSession — muted video mixes with background audio
│   ├── VideoPlayerPool.swift       # Singleton AVPlayer pool (max 3)
│   ├── NotificationManager.swift   # UNUserNotificationCenter builder
│   ├── NotificationScheduler.swift # 4 trigger types + 2/day quota
│   ├── NotificationDelegate.swift  # In-app notification handling
│   ├── ShareHUDManager.swift       # UIWindow at .alert+1 hosting ShareHUDView during share operations
│   └── AnalyticsService.swift      # Native-only telemetry — local event counters (PersistenceService) + os_signpost for MetricKit/Xcode Organizer rollup
│
├── Extensions/
│   ├── View+Extensions.swift       # cardShadow, onShake, color helpers, premiumGoldBackground (paywall gold gradient + glow)
│   └── PHAsset+Extensions.swift    # fileSize, isScreenshot, isScreenRecording
│
└── Assets.xcassets/                # Icons, colors, images
```

---

## Color Palette

All UI colors must come from one of these sources. Do not hardcode other color values.

### Swipe Action Colors
```swift
// View+Extensions.swift
static let swipeGreen  = Color(red: 0.2,  green: 0.8,  blue: 0.4)   // #33CC66 — keep
static let swipeRed    = Color(red: 0.95, green: 0.3,  blue: 0.3)   // #F24D4D — delete
static let swipeBlue   = Color(red: 0.25, green: 0.55, blue: 0.95)  // #40 8CF2 — snooze (Later)
static let swipeYellow = Color(red: 1.0,  green: 0.8,  blue: 0.2)   // #FFCC33 — celebration particles only (TrashCelebrationView)
```

### Filter Category Colors
```swift
// FilterCategory.swift
.all:               .gray
.screenshots:       .blue
.screenRecordings:  .purple
.largeVideos:       .orange
.blurryPhotos:      .red
.burstPhotos:       .cyan
```

### Shuffle Accent Gradient
```swift
// View+Extensions.swift
static let shuffleAccentStart = Color(red: 0.2, green: 0.5, blue: 1.0)
static let shuffleAccentEnd   = Color(red: 0.5, green: 0.2, blue: 0.9)
// Used by: shuffleCapsule (FAB fill + active glow border), shuffleBadge
```

### Surfaces
```swift
// Dark background (splash, onboarding)
Color(red: 0.1, green: 0.1, blue: 0.12)       // #1A1A1F

// Cards — respects system light/dark mode
Color.cardBackground  →  UIColor.systemBackground

// Tab bar
Native iOS TabView (.tabItem) — iOS 18 renders the floating capsule style automatically
```

### Gradients
- Use `LinearGradient` for backgrounds and overlays
- Cards use `shadow(color: .black.opacity(0.1), radius: 8, y: 2)`

### Typography
```swift
// Brand / large headings
.system(size: 32, weight: .bold, design: .rounded)

// Section headers  → .headline or .title2
// Metadata         → .caption or .caption2
// Numeric badges   → .contentTransition(.numericText())  // animated counters
```

---

## Navigation

```
SplashScreenView
    ├── [first launch]    → OnboardingView (5 steps) → set hasCompletedOnboarding = true
    └── [returning user]  → ContentView

ContentView: TabView(selection: $selectedTab)   ← native iOS TabView with .tabItem
    Tab 0 — SmartFiltersView
        └── tap category → loadPhotos(filter:) → selectedTab = 1
    Tab 1 — SwipeStackView    (main experience)
        └── pinch-to-zoom on top card; tab bar hides via .toolbar(.hidden, for: .tabBar)
    Tab 2 — ReviewBinView
        └── tap item → fullScreenCover → FullScreenMediaView

Deep linking:
    NotificationDelegate → NotificationCenter.default.post(name: .notificationNavigate)
    ContentView .onReceive → selectedTab = payload
```

No `NavigationStack` or `NavigationView` is used at the root level. Tab switching is the primary navigation. `fullScreenCover` is used for full-screen media preview only.

**Review Bin detail viewer — progressive loading:** `ReviewGridItemView`'s tap handler passes its own already-decoded thumbnail (`onTap: (UIImage?) -> Void`) into `ReviewBinViewModel.SelectedMedia`, which `FullScreenMediaView` seeds its `image` `@State` with at `init` — the viewer never opens on a blank black screen. `load()` then calls `PhotoLibraryService.loadFullScreenImage()` (`.opportunistic` delivery, screen-resolution `targetSize`, `.aspectFit` contentMode) to upgrade in place. This replaced a prior version that requested `PHImageManagerMaximumSize` via `.highQualityFormat` — a multi-second decode of the full original for a view nobody can zoom into, with no placeholder shown while it loaded. For video, the same `image` state doubles as the poster frame shown while the `AVPlayer` prepares.
Mirroring `PhotoCardView`'s `showImageSpinner`/`showLoadingSpinner` pattern: a small spinner badge only appears over the thumbnail if the final-quality image/player hasn't landed within 500ms (`isFinalReady`, set on the non-degraded `loadFullScreenImage` callback or once the `AVPlayer` is assigned) — avoids a spinner flash on the common near-instant case while still giving feedback on a genuinely slow (e.g. iCloud) fetch. This delayed-badge mechanism is `View+Extensions.swift`'s `delayedIndicator(isReady:after:indicator:)` — a `ViewModifier` generalizing the pattern for new call sites (PhotoCardView's own two spinner instances are left as-is; that file is performance-critical and already tuned, so migrating them wasn't worth the regression risk for a pure dedup).

`isFinalReady` must be set on failure too, not just success — an earlier version only set it on the happy path, so a load that never resolved (deleted/corrupt asset, `requestPlayerItem` returning nil, offline with no local proxy) left the spinner running forever. Both `load()` branches now have an explicit failure path (`PHImageManager` calling back with `playerItem == nil` / `loadFullScreenImage` calling back with `image == nil`), and `PhotoLibraryService.loadFullScreenImage` itself was fixed to always invoke its completion (it used to silently drop the nil-image callback). A per-view 8s failsafe `Task` force-sets `isFinalReady = true` regardless, closing one residual gap neither branch can cover on its own: offline mode with only a degraded local proxy available delivers that one frame and PHKit never calls back again, so there's no second callback to hang the fix on.

`FullScreenMediaView` also cancels its in-flight `PHImageRequestID` (one shared `requestID` — `item.isVideo` is fixed per instance, so only one of `load()`'s two branches ever runs) in `onDisappear`, guarded by an `isDismissed` flag checked at the top of each completion handler — without this, dismissing the viewer while a video was still loading could result in a new `AVPlayer` being created and started (audible playback) after the screen was already gone, since PHKit cancellation doesn't guarantee an in-flight handler won't still fire. The failsafe `Task` is itself stored and cancelled in `onDisappear` too — otherwise its closure keeps the view's `@State` (including a live `AVPlayer`) referenced for up to 8s after dismissal purely by still counting down.

`DelayedIndicator`'s own `.onAppear` closure only fires once per mount, so the `isReady` value it captures at that moment is frozen for the Task's lifetime — the `Task` therefore does not gate on `isReady` at all before setting `showIndicator = true`; the actual hide/show decision is the separately-evaluated, always-live `showIndicator && !isReady` check in `.overlay`, which re-runs on every body render. Do not add a `guard !isReady` inside the delayed `Task` expecting it to see live updates — it can't.

The tab bar is the native iOS `TabView` — on iOS 18 it renders automatically as the floating capsule style (as in WhatsApp / Instagram). Content views stop above the tab bar via the safe area injected by `TabView`; no manual height math needed.

### Layout Direction — Pinned to LTR App-Wide

`SwipyApp.swift` sets `.environment(\.layoutDirection, .leftToRight)` on the root `WindowGroup` content. On an RTL device (Hebrew), iOS mirrors the entire root coordinate space — this flips not just `Edge.leading`/`.trailing`-based transitions but was observed to flip raw `.offset(x:)`-based ones too, since the mirroring happens above where SwiftUI's `\.layoutDirection` environment alone can counteract it; overriding the root's layout direction is the only fix that reliably holds for both. Hebrew text itself still renders correctly (Unicode bidi text shaping is independent of this) — only *container* layout (HStack ordering, `.leading`/`.trailing` resolution, transition direction) is pinned to LTR everywhere, so "forward" always means right regardless of device language. `AnyTransition.pushForward` (`View+Extensions.swift`) — used by `OnboardingView`'s step transitions and `SplashScreenView`'s onboarding↔ContentView handoff — relies on this: it's plain `.move(edge: .trailing/.leading)`, safe only because layout direction is pinned upstream.

---

## Pagination & Image Loading

- **Initial load**: 50 items (200 for blurry, 500 for burst — needed for VNFeaturePrint chain analysis)
- **Page size**: 30 items per subsequent page
- **Watermark**: next page loads when ≤ 15 items remain in `photoStack`
- **PHFetchResult** is treated as a lazy index — never fully enumerate it
- **NSCache**: `countLimit = 10` online / `30` offline; no `totalCostLimit` — OS evicts under memory pressure; entries keyed by asset `localIdentifier`
- **Precaching**: After each swipe, top-8 images are loaded into NSCache via `precacheNextImages()`; `warmUpCache()` hints the OS decode pipeline 20 items ahead
- **VideoPlayerPool**: max 3 `AVPlayer` instances; stale eviction via `warmUp()`; players are **paused (not released)** on tab switch so video resumes instantly on return; `drainAll()` only before PHPhotoLibrary deletion

**Zero-latency prefetch decoding:** `precacheNextImages()`/`prepareUpcomingCards()`'s shared completion path (`PhotoStackViewModel.handlePrefetchedImage(_:isDegraded:item:onFinal:)`) runs `UIImage.prepareForDisplay(completionHandler:)` (iOS 15+, deployment target is 18.2) on every final (non-`isDegraded`) `requestCardImage` result before it's cached/published — this forces the JPEG/HEIC bitmap decompression off the main thread ahead of time, so a card's first SwiftUI composite never pays a decode cost. Falls back to the original image if `prepareForDisplay` returns nil (undocumented but possible for unsupported formats). The degraded (`.opportunistic` first-pass) result skips this — it's about to be replaced by the final pass, so predecoding a throwaway intermediate is wasted work. `prepareForDisplay`'s completion handler is `@Sendable`; the cache write and all `@Published` state mutations happen inside the same `Task { @MainActor in }` hop, not in the closure body directly, or Swift 6 flags the `photoService` property access.

Chosen over a manual `kCGImageSourceShouldCacheImmediately`/`CGContext`-render approach (the pre-iOS-15 workaround for the same problem) per this project's Native-First principle — `prepareForDisplay` is Apple's first-party, tested replacement, and the deployment target has no compatibility reason to avoid it.

For **iCloud-only assets** still downloading, no amount of local predecoding helps — there's nothing to decode until the bytes arrive. `armThumbnailBridge(for:)` proactively fires the existing fast local-only `PhotoLibraryService.loadThumbnail()` (never touches iCloud) for items in the prefetch window whose full asset isn't locally available, caching results in a small dedicated `PhotoLibraryService.thumbnailCache` (separate `NSCache` from `cardCache` — different resolution under the same asset-ID key). Local items skip this entirely; their full-res image is already `prepareForDisplay`-ready by the time they're shown, so a separate thumbnail tier buys them nothing. `PhotoCardView.loadImage()`'s own Pass-1 thumbnail fetch checks this cache first before firing a new `PHImageManager` request — closes what was otherwise a frequent (not rare) dual-fetch race, since `loadImage()`'s fallback fires for essentially every card near every swipe (once per card at its first entry into the visible 3-deep stack), independently of and uncoordinated with the ViewModel's own prefetch.

**`isCloudOnly` dead-code bug (fixed):** The bridge above originally gated on `item.isCloudOnly` (`PhotoItem`'s stored flag) — a code-review pass found this field is never assigned anywhere in the codebase. Its doc comment claimed it was "Set by `applyOfflineModeFilter()`," but that function was removed when offline mode was rewritten around `scanLocalUniverse` (a streaming local-only scanner), and the replacement never carried the assignment forward — the field silently defaults to `false` forever, and it's also scoped to a different concept than what the bridge needs: `isCloudOnly` was always specifically an *offline-mode* signal ("has this asset been locally cached for offline browsing yet"), not a general "would this asset need a network fetch right now" check, so even a correctly-populated `isCloudOnly` would stay `false` throughout ordinary online swiping — the bridge's actual target case. Fixed by having `armThumbnailBridge` call `PhotoLibraryService.isLocallyAvailable(_:)` directly instead — an existing, already-used-elsewhere (offline-mode filtering, snooze staging) synchronous `PHAssetResource`-backed check, cheap enough (Photos-DB metadata read, no I/O) for the ~8-item prefetch window this runs over. `PhotoItem.isCloudOnly` and its own separately-broken offline-mode "iCloud badge" UI (`PhotoCardView`) were left untouched — that's a pre-existing gap predating this feature, not introduced by it, and out of scope here.

`PhotoLibraryService.cardTargetSize`'s initial `lazy var` seed formula now mirrors `CardStackView.body`'s own `cardW`/`cardH` calculation exactly (same 9:16-aspect-constrained formula, `UIScreen.main.bounds` standing in for `GeometryReader`'s size — a close match since the app is portrait-locked) instead of the old flat `screenHeight * 0.65` approximation with no aspect-ratio awareness. This matters because `cardCache`/`thumbnailCache` are keyed only by asset ID with no size component and have no invalidation path — a code-review pass found that any image cached before `CardStackView.onAppear` first corrects the size (which cold-start prefetch, called synchronously from `PhotoStackViewModel.init()`, does) would otherwise be served at the wrong size for the rest of the session, hitting exactly the first-impression cards of every launch. Aligning the seed formula closes this for the overwhelming majority of cases without needing a re-request/invalidation mechanism; `updateCardTargetSize(_:)` remains as a correction for any residual device-specific difference. `requestCardImage`'s `resizeMode` is explicitly set to `.fast` (previously left at PhotoKit's unstated default) — `.exact` was considered and rejected: it forces PhotoKit to always produce a bitmap at precisely the requested aspect ratio, which is the slower of the two documented modes, while `PhotoCardView` already applies `.resizable()`/`.scaledToFit()`/`.aspectFill()` to handle the final fit regardless of the source's exact dimensions.

**`activeRequests` cleanup race (fixed):** `handlePrefetchedImage`'s async `prepareForDisplay` hop widens the window between a `PHImageManager` completion firing and its `activeRequests` entry being cleared. A code-review pass traced a real race: if a second `requestCardImage` call for the same still-in-flight item overwrites `activeRequests[item.id]` with a fresh request ID while the first call's `prepareForDisplay` is still decoding, the first call's completion — which used to call `activeRequests.removeValue(forKey:)` unconditionally — would delete the *second* call's still-live tracking entry instead of its own. If that item was then swiped away before the second request resolved, `cancelRequest` would never find it, leaking an in-flight `PHImageRequestID` (same-asset target, so not a wrong-image risk, just wasted/uncancelled work). Fixed by threading the originating `PHImageRequestID` through to `handlePrefetchedImage` (captured via a `var` assigned before the closure runs, read inside it once `requestCardImage` has returned) and only clearing `activeRequests[item.id]` if it still equals that ID.

---

## Smart Filter Counting (2-Phase)

Phase 1 (fast, runs first): metadata-only `PHFetchRequest` counts, capped at 100 (matches the "99+" display ceiling) — instant for every category, including `.blurryPhotos`/`.burstPhotos` where this is only a *candidate-pool* estimate (all non-screenshot images), not a real match count.

Phase 2 (accurate, background): runs for all three expensive categories — `.largeVideos` (file-size resource inspection, always runs) and `.blurryPhotos`/`.burstPhotos` (cache-first via `BlurBurstCacheService`/`BlurBurstScanEngine`, capped at 100) — in parallel via `async let` in `PhotoStackViewModel.refreshCategoryCounts()`. Results persist to `Documents/categoryCounts.json` so a warm cache is available immediately on the next launch, before Phase 2 even reruns. `refreshCategoryCounts()` is itself guarded by `isRefreshingCounts` so its two real-world call sites (the initial `loadPhotos()` path and `SmartFiltersView`'s `.task`) can't fire two concurrent Phase 2 scans on a fresh launch.

`PhotoStackViewModel.categoriesRecalculating: Set<FilterCategory>` (not a single large-video-only bool) drives the dim+spinner per category in `SmartFiltersView`. Never block Phase 1 counts waiting for Phase 2 to finish.

**The dim+spinner only shows for a category the first time its accurate count is ever computed** (`expensiveCategories.subtracting(cached.keys)` in `refreshCategoryCounts()`, where `cached` is the snapshot of `cachedAccurateCounts` taken before this run). Once a category has a previously-verified value, Phase 2 re-runs silently in the background on every subsequent refresh — no spinner, no dimming — and the badge itself still animates via `.contentTransition(.numericText())` if the number changes. This matters most for `.blurryPhotos`/`.burstPhotos`, whose Phase 1 estimate (candidate-pool size) can be 10x+ larger than the real Phase 2 count — silently swapping that number out with zero affordance on a first-ever cold calculation would read as a UI glitch, not a refinement.

`SmartFiltersView` only triggers `refreshCategoryCounts()` in three cases — first-ever load this session, after a swipe/keep/delete/snooze/undo action flags `hasPendingCountUpdate` and the user returns to the tab, or an explicit pull-to-refresh. Simply switching tabs back and forth without any of those does not re-trigger it — the in-memory `categoryCounts` is reused as-is. The first-load check is `PhotoStackViewModel.needsInitialCountRefresh` (`FilterCategory.allCases.contains { categoryCounts[$0] == nil }`), **not** `categoryCounts.isEmpty` — cold start no longer pre-warms counts at all (see Cold-start swipe jank below), but `PhotoStackViewModel.init()` still seeds `categoryCounts` from disk with the 3 persisted Phase-2 categories (large videos/blurry/burst), which makes the dict non-empty while `.all`/`.screenshots`/`.screenRecordings` (never persisted — always computed fresh by Phase 1) are still unset for a returning user. `.isEmpty` would wrongly treat that partial state as "already loaded" and leave those three badges stuck at 0 for the whole session. `needsInitialCountRefresh` is a single ViewModel-owned computed property — `SmartFiltersView`'s `.task` is its **only** caller. `resetAndLoad()` (called from `PhotoStackViewModel.init()` on every cold start) used to have four internal `if needsInitialCountRefresh { refreshCategoryCounts() }` fallbacks of its own (offline mode, `.largeVideos`, `.blurryPhotos`/`.burstPhotos`, default filter), added as a self-healing guard against a first-ever-install/cache-miss leaving `categoryCounts` permanently incomplete. Those were removed: since `.all`/`.screenshots`/`.screenRecordings` are never persisted to disk, `needsInitialCountRefresh` is `true` at the start of **every** cold start for **every** user, not just a fresh install — so those fallbacks fired the full Phase 2 Vision/CIFilter scan unconditionally right after the first page of swipe cards loaded, every single launch, reintroducing the exact cold-start jank this whole effort was fixing. There is no actual need for the swipe-loading path to trigger this at all — nothing outside `SmartFiltersView` reads `categoryCounts`, so an unpopulated dict simply stays unpopulated (no stuck state) until the user opens that tab, which computes it fresh on demand.

### Blurry/Burst Scanning — Bounded Concurrency + Verdict Cache
Both categories used to decode and analyze candidate photos **sequentially, one at a time** on every visit — the root cause of a reported hang where a "99+" badge led into a long unresponsive load with a bare spinner and no progress signal. Fixed via:
- **`BlurBurstCacheService`** — disk-backed verdict cache (Caches dir, debounced writes) built on a private generic `DebouncedJSONStore<Value: Codable>` (lock-protected read/mutate, single coalesced write ~2s after the last mutation). Two separate stores/files, not one: `verdicts` (`[assetID: Bool]` blur+burst, small/stable) and `featurePrints` (`[assetID: Data]` serialized `VNFeaturePrintObservation`s via `NSKeyedArchiver`/`requiringSecureCoding: true`, larger and growing) — split so a blur/burst-only write never forces re-encoding the much bigger, separately-growing feature-print blob file, and vice versa. A verdict/print is stable for the asset's lifetime once computed, so it's only computed once — see `photoLibraryDidChange` below for how edits still invalidate this correctly. `DebouncedJSONStore.mutate` does the dirty-flag set + pending-save cancel/reassign entirely inside its lock — an earlier version of `scheduleSave()` did the cancel/reassign *outside* the lock, which was a real data race once `setFeaturePrint` started calling it from up to 6 concurrent `TaskGroup` children per burst batch. `featurePrints` is additionally tagged with `schemaVersion` (a manually-bumped constant, checked in `init()` — bumped only when the app's Vision feature-print usage actually changes, e.g. a different request revision; an OS-version-string proxy was tried first and rejected for wiping the cache on every iOS point release regardless of whether the model actually changed). A schema mismatch matters because `BurstAnalyzer.analyze()`'s `try? p1.computeDistance(&distance, to: p2)` leaves `distance` at its initial `0` on failure, and `0 < visualDistanceThreshold` is `true` — so an incompatible cross-schema comparison would silently default to "similar" and mis-group unrelated photos into a burst with zero error signal. On a mismatch, only `featurePrints` is wiped (not `verdicts`, which carries no such risk) — costs one re-computation pass on the first Smart Filters visit after a schema bump, not a full re-scan.
- **`BlurBurstScanEngine`** — a plain (non-`@MainActor`) class, like `BlurDetector`/`BurstAnalyzer`, so its `CIFilter`/Vision work genuinely runs off the main thread even when awaited from a `@MainActor` caller. Scans with bounded concurrency (`TaskGroup`) instead of one image at a time, and uses `loadImageForAnalysis` (`.fastFormat`, no network) instead of the card-display path's `.highQualityFormat`+network — an iCloud-only photo with no local proxy is skipped for that pass, never blocks the scan waiting on a download. `maxConcurrency` is a per-call parameter (`scanBlurry`/`countBlurry`/`BurstAnalyzer.analyze`, default `BlurBurstScanEngine.defaultConcurrency` = 6) — interactive callers (`scanUntilFull`, Phase 2 accurate counts) use the default since throughput matters when the user is staring at `SmartFiltersView`'s spinner; `startBackgroundBlurBurstPrescan()` passes 3, since nothing there is time-sensitive and it otherwise competes with onboarding's own animations for CPU (see below). Concurrency (throughput) and QoS (scheduling priority) are independent knobs — `refreshCategoryCounts()`'s Phase 2 blurry/burst count keeps concurrency at 6 but explicitly runs that work in a `Task.detached(priority: .background)` (see Cold-start swipe jank below), so it never competes with `.userInitiated`/main-thread work regardless of how many candidates it's scanning.
- **`BurstAnalyzer`** — the sequential chain-grouping algorithm is unchanged (each item's grouping decision depends on the previous group's state, so it must re-run in full every call — burst membership is relational, not a stable per-asset property, and can't be short-circuited the way a blur verdict can). But the expensive `VNFeaturePrintObservation` computation per photo is now precomputed concurrently up front (bounded `TaskGroup`, same per-call `maxConcurrency` parameter as above) and is itself cache-first via `BlurBurstCacheService.featurePrint(for:)`/`setFeaturePrint(_:for:)` — a previously-computed print is reused instead of re-running Vision, so only genuinely new-to-the-cache assets cost anything. The grouping pass itself is then pure CPU (dictionary lookups + vector distance) regardless of cache state.
- **`PhotoStackViewModel.startBackgroundBlurBurstPrescan()`** — triggered from `startOnboardingScan()`'s own completion (not fired in parallel with it — see below), walks the full library at `.background` priority, `maxConcurrency: 3`, so both categories are already warm by the time the user taps into them. Cache-first makes repeat runs (e.g. re-triggered on library changes) cheap. Shares a single lock (`isBlurBurstScanActive`, claimed/released via `tryAcquireBlurBurstScan()`/`releaseBlurBurstScan()`) with `refreshCategoryCounts()`'s Phase 2 blurry/burst counting — only one of the two touches `BlurBurstScanEngine`/`BurstAnalyzer` at a time; whichever loses the race skips its blur/burst work for that round rather than duplicate it.
- **`photoLibraryDidChange`** — incremental cache invalidation via `BlurBurstCacheService.invalidate(assetIDs:)` (not a full wipe), called for two distinct cases: removed assets (deleted externally — `details.removedObjects`) and changed assets (in-place edits — `details.changedObjects`). The latter matters because a `PHAsset`'s `localIdentifier` survives a crop/filter/markup edit in Photos.app even though the pixels don't, so without this a cached blur/burst verdict or `BurstAnalyzer` feature print would silently keep serving pre-edit analysis forever. Newly inserted assets trigger a fresh (cheap, cache-first) prescan run. The *accurate-count* cache (`cachedAccurateCounts`/`categoryCounts.json`) is only wiped when `removedIDs`/`insertedIndexes` are actually non-empty — **not** merely when `details.hasIncrementalChanges` is true, since that flag is also true for a plain `changedObjects`-only update (e.g. a favorite toggle): per Apple's docs, `hasIncrementalChanges` is false only in the rare case the old fetch result must be wholesale-replaced, not whenever a change is "just metadata." Gating on it alone (an earlier version of this fix) still wiped the accurate-count cache on every trivial edit; gating on real insertions/removals is what actually stops a metadata-only `PHChange` callback from dropping an already-accurate count back to a Phase-1 estimate + spinner.

**Cold-start swipe jank (fixed):** For a returning user, `SplashScreenView.onAppear` used to call `refreshCategoryCounts()` unconditionally whenever Photos permission was already granted, and `ContentView` defaults `selectedTab = 1` (`SwipeStackView`) — so the user landed on the card stack and started swiping while Phase 2 was still running in the background. First fix: its blurry/burst accurate-count computation (`accurateBlurryCount`/`accurateBurstCount`) ran as a plain `async let` inside the outer `Task.detached(priority: .userInitiated)`, inheriting that QoS — unlike `largeVideoCount` two lines above it, which was already correctly wrapped in `Task.detached(priority: .background)`. At `.userInitiated`, up to 6 concurrent CIFilter/Vision pipelines competed with the main thread for the same performance cores during the first ~8-10s after cold start, causing dropped frames during drag-gesture tracking. Wrapping the blurry/burst `async let` pair in its own `Task.detached(priority: .background)` (matching `largeVideoCount`) cut this to ~5s but didn't eliminate it — `BurstAnalyzer.analyze()` had no cache short-circuit at the time, so every cold start still ran genuine Vision feature-print work across up to several hundred candidates (paginated in batches of 500 in `accurateBurstCount`), and sustained multi-core load at that volume can still cause perceptible jank (thermal throttling, GPU/ANE contention with Core Animation) independent of GCD QoS scheduling.

The next fix was to stop running Phase 2 (and Phase 1) on cold start at all: `SplashScreenView.onAppear` no longer calls `refreshCategoryCounts()` — `PhotoStackViewModel.init()`'s `loadCachedAccurateCounts()` still seeds `categoryCounts` from disk synchronously so Smart Filters shows last-known numbers instantly if visited, but a fresh scan now only fires from `SmartFiltersView`'s own `.task`/`.onAppear`/`.refreshable` triggers — i.e. only when the user is actually looking at that screen, never while landing on/swiping the main card stack. Combined with the `BurstAnalyzer` feature-print cache above, even that on-demand scan is cheap on repeat visits.

A third, more fundamental instance of the same bug was found afterward: `resetAndLoad()` (called from `PhotoStackViewModel.init()` on every cold start, regardless of which tab the user lands on) had its own four internal `if needsInitialCountRefresh { refreshCategoryCounts() }` fallbacks, added to guard against a first-ever-install leaving `categoryCounts` permanently incomplete. Since `.all`/`.screenshots`/`.screenRecordings` are never persisted to disk, `needsInitialCountRefresh` evaluates `true` at the start of literally every cold start for every user — not just a fresh install — so these fallbacks fired the full Phase 2 scan unconditionally right after the first page of swipe cards loaded, on every single launch, silently reintroducing the exact jank the `SplashScreenView` fix above was meant to eliminate. Removed entirely: nothing outside `SmartFiltersView` reads `categoryCounts`, so there is no correctness reason for the photo-loading path to trigger this at all — an unpopulated dict just stays unpopulated (not stuck, not broken) until the user actually opens Smart Filters.

**Onboarding CPU spike (fixed):** `startOnboardingScan()` and `startBackgroundBlurBurstPrescan()` used to fire in parallel from `OnboardingView.requestPermission()`, right at permission grant — while the user is still on the animated SwipeDemo/Scan steps. Both are genuinely CPU-heavy (the former's Phase 2 accurate large-video count used an uncapped `DispatchQueue.concurrentPerform`; the latter runs 6-concurrent CIFilter/Vision pipelines), and running simultaneously measured ~160% sustained CPU with visible UI jank. Fixed by: (1) sequencing — `startBackgroundBlurBurstPrescan()` is now called from the *end* of `startOnboardingScan()`'s own `Task.detached` body, after `analyzeFavorites()` completes, never in parallel; (2) `startOnboardingScan()`'s outer task dropped from `.utility` to `.background`; (3) its video-count phase replaced `DispatchQueue.concurrentPerform` (no cap, doesn't respect Swift Task priority) with a bounded `TaskGroup` (cap 4); (4) the prescan's `maxConcurrency` reduced to 3 (interactive paths keep the default 6). As a side effect, this also fixed a latent gap where the Settings-recovery path (`OnboardingView`'s `scenePhase` re-check after a denied→granted permission flow) called `startOnboardingScan()` but never triggered the prescan at all — now it does, automatically, since the prescan lives inside `startOnboardingScan()`.

**Fresh-install first-swipe CPU spike (fixed):** Even after the fix above sequenced `analyzeFavorites()` and `startBackgroundBlurBurstPrescan()` so they don't run *in parallel*, a fresh install still measured a real CPU/GPU spike and dropped drag frames for the first ~30s of actual swiping — resolving permanently after that and never recurring on later launches. Root cause was structural, not a QoS/scheduling bug: (1) `startBackgroundBlurBurstPrescan()`'s `prescanBatches()` walks the **entire** library with no cap (unlike `refreshCategoryCounts()`'s Phase 2, capped at 100) — on a fresh install `BlurBurstCacheService`'s on-disk verdict/feature-print cache is completely empty, so every asset needs a real `CIFilter`(CIEdges)/`VNFeaturePrintObservation` computation instead of an O(1) cache hit; on every later launch the same walk hits cache for nearly every asset and is near-instant, which is exactly why the jank was fresh-install-only. (2) `AestheticScoringService.buildPersonaBlocking()` (persona-building for the aesthetic score badge) is a **synchronous, unconcurrent** `for` loop over up to 200 Favorites — real `PHImageManager`(`isSynchronous: true`)+CIFilter+Vision work, one item at a time, no `TaskGroup` — unlike every other scan in the codebase. `startOnboardingScan()` used to `await` this before chaining into the prescan, serializing two expensive scans back-to-back instead of overlapping their (already-bounded) work with the user's onboarding navigation. (3) `.background` GCD QoS only deprioritizes CPU thread scheduling — it does not deprioritize Metal/GPU or Neural-Engine contention, and CIFilter/Vision work competes directly with Core Animation's compositor for those same resources on the very frames a drag gesture needs to hit 120Hz.

Fixed by:
- **Persona build fully decoupled from cold start.** `resetAndLoad()`'s and `startOnboardingScan()`'s eager `analyzeFavorites()` calls were replaced with `scheduleDeferredPersonaBuild()` — a `personaBuildScheduled`-guarded `Task.detached(priority: .utility)` that sleeps 5s before calling `analyzeFavorites()`, giving the first real swipes a clean window. `analyzeFavorites()` is already idempotent (no-ops once `persona?.isReady == true` or while `isAnalyzing`), so scheduling this from both cold-start entry points (returning user via `resetAndLoad`, fresh install via `startOnboardingScan`) is safe; `personaBuildScheduled` resets after each attempt completes (even a no-op one) so a premature attempt — e.g. the `resetAndLoad`-triggered one firing before onboarding has even requested permission — doesn't permanently block the real one from scheduling later. `startBackgroundBlurBurstPrescan()` in `startOnboardingScan()` no longer waits on this at all.
- **`prescanBatches()` blurry chunk size reduced** from 300 to 30 — blur verdicts are fully independent per-asset so a smaller chunk costs nothing in quality, and gives the gesture guard below far more frequent checkpoints. **Burst chunk size stays at 500**, deliberately kept aligned with `accurateBurstCount()`'s own page size: an earlier version of this fix dropped it to 100, but `BurstAnalyzer.analyze()` has no cross-call state, so a smaller burst chunk risks splitting a genuine long burst across a page boundary — and because both burst-scanning entry points write into the same `BlurBurstCacheService` cache, a boundary artifact from a *lower-priority background* scan could silently corrupt the *accurate, user-facing* Smart Filters count. Keeping both at 500 means they always agree on chain boundaries. All five tuning values (persona-build delay, gesture-poll interval, inter-chunk pause, blur/burst chunk sizes) are named constants in `PhotoStackViewModel.ScanTuning`, not inline literals.
- **Gesture-priority guard.** `PhotoStackViewModel.isUserInteracting` is a plain (deliberately **non-`@Published`**) `Bool`, set directly by `CardStackView`'s drag/pinch `.onChanged`/`.onEnded` handlers (mirroring the existing `viewModel.cancelPrefetch()` call already made from the same handlers). `prescanBatches()` checks it before starting each chunk and blocks (`Task.sleep` polling loop, 150ms) for as long as it's true, plus an unconditional 100ms pause between every chunk regardless. It is intentionally **not** `@Published` — `ObservableObject` invalidation is per-object, so a `@Published` flag here would fire `objectWillChange` on every gesture frame's worth of mutations and force a full re-diff of the card `ForEach`, regardless of whether any view actually reads it in `body`. This is the exact mechanism documented above under "Swipe Gesture Performance" (Round 4, `item.fileSize` in `PhotoCardView.Equatable`) that caused a real on-device regression — the fix here deliberately avoids reintroducing that class of bug.

**Smart Filters navigation jank (fixed):** All the fixes above hardened `startBackgroundBlurBurstPrescan()` (onboarding / new-asset-insert triggered) against gesture contention, but `refreshCategoryCounts()`'s own Phase 2 blurry/burst path — triggered by simply opening the Smart Filters tab — was never given the same treatment, despite scanning through the identical `BlurBurstScanEngine`/`BurstAnalyzer` engines. Reported symptom: stuttery scrolling inside Smart Filters while its own Phase 2 scan ran, and severe swipe-gesture lag (>100-150% CPU) if the user navigated back to the card stack mid-scan — i.e. exactly the class of jank `isUserInteracting`-gating exists to prevent, just missing from this one call path. Two compounding issues, fixed together:
- **No gesture-aware pause.** `accurateBlurryCount()`/`accurateBurstCount()` paginated straight through with no check of `isUserInteracting` at all. Fixed by extracting the poll-and-back-off loop out of `prescanBatches()` into a standalone `PhotoStackViewModel.waitForGestureIdle(viewModel:)` (same `ScanTuning.gestureInteractionPollInterval`/`gestureWaitTimeout` constants), called from `prescanBatches()` and from the top of both `accurateBlurryCount()`'s and `accurateBurstCount()`'s pagination loops, plus the same `interChunkYieldDuration` pause between their pages — so a Phase 2 scan backs off identically to the prescan the moment `CardStackView`'s drag/pinch handlers set `isUserInteracting`.
- **Double concurrency budget.** Phase 2 ran `accurateBlurryCount`/`accurateBurstCount` as two parallel `async let`s, each internally spending up to `BlurBurstScanEngine.defaultConcurrency` (6) — worst case 12 simultaneous CIFilter/Vision pipelines, double the budget either engine was tuned for. Changed to run sequentially (`await` one, then the other) inside the same `.background` `Task.detached`. **Correction from a later code-review pass:** this isn't actually free — it roughly doubles how long the shared `isBlurBurstScanActive` lock is held per call (sum instead of max of the two scan durations), which both increases how often a concurrent `startBackgroundBlurBurstPrescan()` loses the race and skips its cache-warming pass, and doubles the dim+spinner's visible duration on a category's first-ever accurate computation. Accepted as a deliberate tradeoff (12-way CIFilter/Vision concurrency was the worse problem), but see the watchdog below for why this couldn't be left unbounded.

Fixing this also surfaced an adjacent correctness bug in the same block: `categoriesRecalculating = []` cleared unconditionally after Phase 2, even on the branch where `tryAcquireBlurBurstScan()` lost the lock to a concurrent prescan and `accurateBlurry`/`accurateBurst` came back `nil` — the dim+spinner affordance would silently disappear over a count that was never actually refreshed. Now each category is only `.remove()`d from `categoriesRecalculating` when it actually receives a fresh value this round; a skipped category stays in the recalculating set and is picked up by the next `refreshCategoryCounts()` call (`needsVisibleRecalc` is recomputed from `cachedAccurateCounts`, which still won't contain it).

**Stuck-spinner watchdog (fixed):** The per-category fix above traded one bug for a narrower one — nothing guaranteed a skipped category's *next* trigger would ever actually arrive. `refreshCategoryCounts()` only re-fires on first-load `.task`, a post-swipe `.onAppear`, or manual pull-to-refresh; no timer or `scenePhase` retrigger exists. A code-review pass found this is realistically reachable on a fresh install specifically: `startBackgroundBlurBurstPrescan()` (fired from onboarding's own completion) can win the scan lock right as the user's very first `.task`-triggered Smart Filters visit loses it, leaving the Blurry/Burst spinner stuck until the user happens to swipe-and-return or manually pull-to-refresh. Fixed with a generation-guarded failsafe `Task` (`ScanTuning.recalculatingSpinnerTimeout`, 20s) spawned alongside `categoriesRecalculating`'s initial set, mirroring `FullScreenMediaView`'s own 8s failsafe pattern for the identical class of problem (see the Review Bin detail-viewer section above). `categoryRefreshGeneration`, bumped at the start of every `refreshCategoryCounts()` call, lets a stale watchdog from an earlier call recognize a newer call has since taken over and no-op instead of clobbering that newer call's legitimate in-progress spinner state — same pattern as `CardStackView`'s `undoGeneration`.

Separately, Phase 1 (`refreshCategoryCounts()`'s outer `Task.detached`, the fast metadata-only counts covering all 6 categories) ran at `.userInitiated` — dropped to `.utility`. Phase 1 is already fast regardless of QoS tier (`PHFetchRequest` counts, not asset analysis), but it fires the instant Smart Filters opens, i.e. exactly when that screen is laying out and about to be scrolled; `.userInitiated` biased the scheduler toward it at the worst possible moment for scroll responsiveness.

See `ARCHITECTURE_SWIPE_LOADING.md` §3b for the full data flow.

---

## Performance Rules

1. **Never enumerate full PHFetchResult** — use index-based access only.
2. **Blur detection input**: Always downsample to 200×200 before running `CIEdges` (`CILaplacian` is macOS-only and returns nil on iOS).
3. **Scoring input**: Downscale to 299×299 before `VNClassifyImageRequest` — full-resolution images (1080p+) make Vision take 10+ seconds per frame.
4. **Concurrent counting**: Use `withTaskGroup` for parallel category counts.
5. **Video pool drain**: Call `VideoPlayerPool.shared.drainAll()` before any PHPhotoLibrary deletion. On tab switch use `pauseAll()` — never `release()` from `onDisappear`, or the pool will be cold on return.
6. **Cache eviction**: Keep only top-8 stack images + the undo item in NSCache; evict everything else.
7. **Background tasks**: All heavy computation must be in `Task.detached` or `withTaskGroup`; results published via `await MainActor.run`.
8. **Streaming results**: Blurry/burst detection must stream one-by-one into the stack — do not wait for full batch.
9. **Animation bleed**: Never wrap `@Published` set insertions in `withAnimation` at the ViewModel level — the ambient transaction bleeds into the card stack and causes cards to animate from wrong positions. Instead, use `.animation(_:value:)` on the specific view subtree that should animate.
10. **State isolation for `.onChanged` gestures**: Never own a per-frame gesture value (`DragGesture`/`MagnificationGesture` translation, scale, etc.) as `@State` on a view that also hosts unrelated, expensive sibling content (`.ultraThinMaterial`, gradients, shadows). Mutating that `@State` re-diffs the *entire* hosting view's `body` on every gesture frame — see "Swipe Gesture Performance" below for the concrete case this bit us on.

### Swipe Gesture Performance — Drag/Pinch State Isolation

Dragging the top card used to spike CPU to 125-130% and drop frames on rapid back-and-forth swipes, while holding the card still cost nothing — a clear sign the cost was tied to `.onChanged` frequency, not drag distance. Root cause: `dragOffset`/`dragRotation`/`pinchScale`/`pinchOffset` lived as `@State` directly on `SwipeStackView` — the view that *also* hosts `SessionSavingsBarView`, the mode badges, the FAB row (shuffle capsule + undo button, each with `.ultraThinMaterial` fills and shadows), and the particle-explosion overlay. Since those values were read inside `SwipeStackView.body`, every `.onChanged` callback (up to 120/sec) forced SwiftUI to re-diff that *entire* screen, not just the card.

Fixed by extracting `CardStackView` (`Views/Main/CardStackView.swift`), which owns every *continuous* gesture value (`dragOffset`, `dragRotation`, `pinchScale`, `pinchOffset`, `pinchAnchor`, `pinchPanOrigin`, `cardSize`) as private `@State` — a drag/pinch frame now only re-diffs this smaller view's `body`. `SwipeStackView` keeps `isPinching`/`isDragging`/`isUndoAnimating` as its own `@State`, passed into `CardStackView` as `@Binding`s: these only flip twice per gesture (start/end), so sharing that storage costs nothing, and it lets the FAB row / tab-bar-hide / pinch-zoom-dim-overlay logic in `SwipeStackView` keep reading them exactly as before without any restructuring there.

One thing that *does* need to cross from `CardStackView` back up to `SwipeStackView` — because it drives UI that lives outside the card (the shake-hint toast counter, the large-file-delete particle burst) — is handed back via a one-shot `onSwipeFinalized(item, action)` callback, fired once per completed swipe (not per frame), so the cost is negligible.

Shake-to-undo is split across the two views: `SwipeStackView.performUndo()` owns the guard checks (`!isDragging`, `!isPinching`) and the `viewModel.undoLastAction()` call, then hands the resulting `SwipeAction` down to `CardStackView` via a `pendingUndoRequest` value (an `UndoRequest`, identified by `UUID` so `.onChange` always fires even if two consecutive undos carry the same action), since the actual re-entry fly-in animation needs `dragOffset`/`dragRotation`, which live in `CardStackView`. A `@State private var undoGeneration` counter on `CardStackView` guards against a stale completion/safety-net timer from an earlier undo clearing `isUndoAnimating` out from under a newer one still in flight.

**A code-review pass flagged (PLAUSIBLE, not confirmed reproducible) that this two-hop design could theoretically let the freshly-promoted top card's first render reflect the new `photoStack.first` before `CardStackView`'s own `dragOffset` had been moved off-screen to match, since the stack mutation and the off-screen positioning happen in different functions across a reactive `.onChange` hop.** A fix was attempted: moving the whole pipeline (guard checks + `viewModel.undoLastAction()` + entry positioning) into `CardStackView` itself, triggered by a plain `undoTrigger: Int` bump from `SwipeStackView`, so the stack mutation and the off-screen positioning became the same synchronous function call. **This was reverted** — a reported on-device drag-smoothness regression appeared immediately after it shipped. Static analysis at the time could not find a mechanism by which it should have affected the drag hot path (`undoTrigger`/`pendingUndoRequest` are both read only inside a rare `.onChange`, never inside `cardStack()`'s `ForEach` body or either `.visualEffect` closure, and `SwipeStackView.body` has no dependency on drag state to begin with, so `CardStackView`'s parameters aren't even re-diffed per drag frame regardless of which undo mechanism backs them) — but the on-device report took priority over a theoretical fix for a low-severity, unconfirmed finding, so the two-hop `pendingUndoRequest` design above is what's actually in the code. If a future investigation identifies the *real* cause of that regression (something not touched by this specific change), the synchronous-undo fix described here could be safely reattempted.

**Round 4 — the actual cause of the reported drag regression turned out to be a different code-review fix, not the undo change.** The same review pass that flagged the undo-timing risk above also found that `PhotoCardView.Equatable`'s `==` was missing `item.fileSize` (the size badge, `item.fileSizeString`, reads it in `body` but it wasn't part of the equality check — a real, if low-severity, staleness gap). The fix — adding `lhs.item.fileSize == rhs.item.fileSize` to `==` — was applied and, unlike the undo change, genuinely did cause the reported regression. Root cause: `PHAsset.fileSize` (`PHAsset+Extensions.swift`) is **not a cheap stored property** — every read calls `PHAssetResource.assetResources(for:)`, a real Photos-framework/database query, not an O(1) lookup. `CardStackView.body` (and therefore `cardStack()`'s `ForEach`, which reconstructs all 3 visible `PhotoCardView`s and runs `.equatable()`'s `==` on each) re-runs periodically **regardless of drag state**, whenever `viewModel` publishes *any* `@Published` change — `ObservableObject` invalidation is per-object, not per-property, and image/score loading (`loadedImageIDs`/`finalImageIDs`/`loadedScoreIDs`) publish continuously during active swiping, since `dragGesture` itself triggers prefetching (`cancelPrefetch()`/`prepareUpcomingCards()`). Each such re-run now paid for up to 6 `PHAssetResource` calls (2 per card × 3 cards) that didn't exist before — frequent enough, and expensive enough per call, to produce a real, measured CPU/smoothness regression. Fixed by removing `item.fileSize` from the comparison entirely — the staleness gap it closed was rare and low-severity; the performance cost of closing it was not worth paying. If it needs revisiting, the right fix is a lightweight signal (e.g. a `@Published` set the ViewModel updates only when it actually detects a size change), never a `PHAssetResource` call inside `Equatable`.

Also fixed as part of the same extraction: the `.animation(value: dragOffset)` / `.animation(value: pinchScale)` / `.animation(value: pinchOffset)` modifiers used to be attached to *all 3* cards in the `ForEach` (only meaningful for index 0), tripling the per-frame `Equatable` diff cost for no visual effect. `CardStackView` now renders background cards (index 1/2, fully static) via a separate `ForEach` with no gesture/offset modifiers at all, and the top card as a single gestured view — the animation modifiers only exist on that one view.

Selectively applied `.drawingGroup()` in `PhotoCardView`'s photo branch (not video) around the two-layer blur-background + sharp-foreground image composite, flattening it into one GPU texture instead of a per-frame CPU composite. Deliberately **not** applied to the video branch — `VideoPlayerView` wraps a live `AVPlayerLayer` via `UIViewRepresentable`, and `drawingGroup()`'s offscreen Metal rendering doesn't reliably composite native `CALayer` content.

**Round 2 — CPU still elevated after the above (`CardStackView` extraction alone wasn't enough):**

1. **`PhotoCardView` still re-rendered every drag frame.** Even with continuous state isolated to `CardStackView`, `CardStackView.body` itself still had to re-run every `.onChanged` frame (something has to apply the new `.offset()`), and every re-run reconstructed a fresh `PhotoCardView` value — including a **freshly-allocated `onShare` closure**. SwiftUI can't compare closures, and a plain `View` struct isn't diffed field-by-field by default, so it conservatively re-invoked `PhotoCardView.body` every frame: rebuilding the badge rows, the image `ZStack`, and re-rasterizing `cardShadow()`'s shadow silhouette over the whole card. Fixed via `PhotoCardView: Equatable` (comparing only the fields that affect its rendered output — `item.id`, `isTopCard`, `isCachedImageFinal`, `aestheticScore`, `snoozeCount`, `isBurstBest`, `isCloudOnly`, `isFavorite` — deliberately excluding `onShare`, uncomparable, and `cachedImage`, which is only read once at `init` to seed `@State` and is never stored) plus `.equatable()` at both `PhotoCardView` call sites in `CardStackView`. SwiftUI now runs the cheap `==` check each frame and skips `body` entirely when nothing rendering-relevant changed.

2. **Unrelated but critical bug found during the above investigation**: extracting the top card out of the `ForEach` (into `if let topItem = viewModel.photoStack.first`) had silently dropped `ForEach`'s `id: \.element.id`. Without an explicit `.id()`, SwiftUI gives a bare `if let` branch purely *structural* identity (same type, same position in the tree) — it does **not** re-key identity to the bound value the way `ForEach(id:)` does. So advancing to a new top card was treated as "the same view, `item` property changed," not a fresh identity: `PhotoCardView`'s `@State` (`image`, `player`, etc.) persisted stale across the swipe, and `.onAppear` never refired to load the new item — the new top card would silently keep showing the *previous* card's image/video indefinitely. Fixed at the time with `.equatable().id(topItem.id)` — **superseded in Round 3 below**, which merged the top card back into a single identity-preserving `ForEach`, making a manual `.id()` unnecessary.

3. **`CardStackView.body` itself still re-ran every drag/pinch frame**, since `dragOffset`/`pinchScale`/`pinchOffset`/`dragRotation` were still read directly inside `.offset()`/`.scaleEffect()`/`.rotationEffect()` calls embedded in its `ViewBuilder` chain — reading `@State` there registers it as a `body` dependency regardless of what's downstream. Fixed by moving the top card's entire transform into a single `.visualEffect { content, _ in content.offset(...).scaleEffect(...).offset(...).rotationEffect(...) }` (iOS 17+). `.visualEffect`'s closure is evaluated during SwiftUI's layout phase, not as part of constructing `body`'s view value — so reads inside it don't register as `body` dependencies. `body` now only re-runs when something it *does* still read changes (`isPinching`/`isUndoAnimating` for gesture attachment, `swipeDirection` — see below), not on every pixel of drag movement. `.visualEffect`'s effects remain `Animatable` and correctly respect ambient `withAnimation` transactions — this is not lost by moving off plain `.offset()`.

4. **`SwipeIndicator` (Keep/Delete/Later badge) needed the same treatment**, since its opacity/scale legitimately must track `dragOffset` continuously (that's the feature) — it can't simply stop reading per-frame state. Split into two pieces: `SwipeIndicator` itself dropped its `offset:` param and internal opacity/scale computation (now pure content — icon/text/capsule for a given `direction`), and `CardStackView` applies opacity/scale via its own `.visualEffect` reading live `dragOffset.magnitude`. The *content* decision (which of the 3 indicators to show) is driven by a new `@State private var swipeDirection: SwipeDirection`, updated inside `dragGesture.onChanged` only `if newDirection != swipeDirection` — i.e. only at the rare 80pt threshold crossings, not on every frame — so `CardStackView.body`'s remaining direct read (for `SwipeIndicator(direction: swipeDirection)`) is cheap and infrequent, while the continuous opacity/scale tracking stays entirely inside the deferred `.visualEffect` closure.

5. **Removing `.animation(value: dragOffset/pinchScale/pinchOffset)`** (keeping them would re-introduce the exact `body`-level reads `.visualEffect` exists to eliminate) required auditing every mutation site for ones that silently relied on the *implicit* animation instead of an explicit `withAnimation{}`. Two did: `dragGesture.onEnded`'s pinch-discard-swipe branch, and `.onChange(of: isPinching)`'s pinch-release reset (`pinchScale = 1.0; pinchOffset = .zero`) — both now wrap their mutation in an explicit `withAnimation(.spring(...))` matching the curve the removed modifier used to supply. Every other `dragOffset`/`dragRotation` mutation site already used explicit `withAnimation` or relied on the "a freshly-inserted view's initial state is never interpolated" rule (fling-completion reset, undo entry's off-screen jump — both happen in the same transaction as a `.id()` change, so they're safe regardless of animation modifiers).

**Round 3 — card promotion (index 1 → 0) elevation, and why the transition approach above was wrong:**

The first attempt at smoothing card promotion (when a swipe removes the top card and the next one takes its place) used a custom `AnyTransition.cardElevation` paired with `.animation(value: topItem.id)` on the separately-rendered top card. This looked right but didn't actually smooth anything — the card still popped. Root cause: `.transition()` only animates a view's *insertion or removal*; it says nothing about how a view's *existing* properties change over time. Because the top card was a structurally separate `if let` block from the background-card `ForEach` (see Round 2 item 2), the promoted card was never "the same view changing its properties" from SwiftUI's perspective — it was always destroy-old/create-new across that boundary, `.id()` or not. A `.transition()` can make an *insertion* fade/scale in from some fixed starting point, but it can't make that starting point continuously match wherever the card visually *already was* a frame earlier as a background card — so at best it was a differently-shaped pop, not real interpolation.

The actual fix: merge the top card back into the same `ForEach(photoStack.prefix(cardStackSize), id: \.element.id)` that renders the background cards (`CardStackView.cardStack(cardW:cardH:)`), with each card's scale/offset/rotation/opacity computed as a pure function of its `index` in that loop, and `.animation(.spring(response: 0.35, dampingFraction: 0.85), value: index)` applied directly. Because the `ForEach` now tracks every card (not just the background ones) by `item.id`, a card promoted from index 1 to index 0 is recognized as *the same persisting view* whose `index` changed — which is the only situation SwiftUI can actually interpolate. `AnyTransition.cardElevation` was deleted entirely (no longer needed — nothing is being inserted/removed here, a persisting view's properties are just changing).

This also fixed a smaller latent inefficiency from Round 2's split architecture: a promoted card used to get a **fresh** `PhotoCardView` identity at the top-card slot (different structural position than where it rendered as a background card), forcing `.onAppear` to refire and reload an image that had already been loaded moments earlier as a background card. With one shared `ForEach`, a promoted card's identity — and its already-loaded `@State` — persists straight through, matching the pre-`CardStackView`-refactor architecture's behavior.

**First cut of the spring was applied unconditionally** (`.animation(.spring(...), value: index)`, unqualified) — since it's on every row in the `ForEach`, this animated *every* card's index change, not just the one arriving at index 0. Swiping card 0 away made card 1 spring up to the front correctly, but also made card 2 visibly spring from its index-2 look to index-1 at the same time — a second, distracting motion nobody asked for; only the card becoming the new top card should move. Fixed by conditioning the animation itself on the *destination* index: `.animation(index == 0 ? .spring(response: 0.35, dampingFraction: 0.85) : nil, value: index)`. A card arriving at index 0 gets the spring; every other card (index 2 → 1, or a freshly-paginated card entering at the back) snaps instantly with no motion at all.

**Second cut re-broke the exact identity continuity the whole fix depends on.** Gesture/drag handling (`.visualEffect`, `.gesture`, `.simultaneousGesture`, the `SwipeIndicator` overlay) was layered on only for the top card via `if index == 0 { applyTopCardGestures(base) } else { base }` inside the `ForEach` row — and the result was that *neither* card animated: the promoted card (1→0) still popped instantly, same as before any of this work. Cause: `if/else` in a `ViewBuilder` is a `_ConditionalContent` **structural branch**, not a value — and per the exact same identity rule documented earlier in this file (the `if let`/`ForEach` split bug), a card crossing from the `else` side to the `if` side is a destroy-old/create-new event to SwiftUI, regardless of matching `item.id` on both sides. A card being promoted to index 0 does exactly that (`else` → `if`) on the very render where the animation was supposed to play — silently destroying the persisting identity `.animation(value: index)` needs, at the one moment it mattered most. Fixed by never branching the view builder on `index`/`isTop` at all: gesture/`.visualEffect` modifiers are now applied **unconditionally** to every row, with `isTop` used only as a ternary *value* inside each modifier's arguments (`.gesture(isTop ? dragGesture : nil)`, `.visualEffect { ... offset(isTop ? dragOffset.width : 0 ...) }`, etc.) so background cards get inert/identity values instead of being structurally excluded. The one exception that's still safe to branch conditionally is the `SwipeIndicator` inside `.overlay { if isTop && isDragging { ... } }` — overlay content is a decorative sibling layer, not a branch around the card itself, so its own insertion/removal never touches the card's identity or `@State`.

---

## Persistence

`PersistenceService` wraps `UserDefaults`. Keys to know:
- `hasCompletedOnboarding` — Bool, gates onboarding
- `keptPhotoIDs` — Set of kept asset local identifiers
- `reviewBinIDs` — array of bin asset local identifiers
- `reviewBinFileSizes` — `[localIdentifier: Int64]` map of frozen file sizes captured at delete time; source of truth for space accounting (avoids iCloud-sync drift)
- `reviewBinSpaceSaved` / `totalSpaceSavedLifetime` — space saved in bytes
- `snoozedPhotos` — `[localIdentifier: snoozeCount]`, drives exponential backoff on re-injection

Notification scheduling caps at **2 notifications/day**. The 6 trigger types are: review bin reminder (24h), photo burst (50+ new photos), milestone (per GB freed), swipe-limit reset (00:01 after daily quota exhausted), weekly cleanup (Sunday 21:30, `repeats: true` — stays OS-guaranteed for lapsed users; `rescheduleWeeklyCleanup()` re-arms it on every foreground purely to swap in a fresh random variant from a 2-message pool for users who are actually opening the app), and an inactivity reminder (72h since last foreground). Swipe-limit reset and inactivity reminder don't count against the daily cap — see `NOTIFICATIONS.md` for full details.

---

## Analytics / Telemetry

`AnalyticsService` is native-only, 100%-on-device product telemetry — no network calls, no third-party SDK (RevenueCat/Mixpanel were evaluated and rejected for launch to preserve the zero-dependency, on-device-only promise). Two layers per `AnalyticsService.shared.log(_:detail:)` call:
1. **Local aggregate counter** — `PersistenceService.analyticsEventCounts` (`[String: Int]`, JSON-over-`@AppStorage`, same pattern as `keptPhotoIDs`). Counts only, no timestamped raw log, to keep the footprint bounded. Inspectable via `AnalyticsDebugView` (`#if DEBUG`-gated, long-press the "Device" section header in `SmartFiltersView`).
2. **`os_signpost`** — MetricKit automatically aggregates these into `MXSignpostMetric`, surfaced in **Xcode Organizer → Metrics** for opted-in users once the app is live on TestFlight/App Store (24–48h delay, aggregated/anonymized, no subscriber code required). Signpost names are static per `AnalyticsService.Event` case (os_signpost requires `StaticString`) — the `detail` parameter (e.g. a `FilterCategory` or `PremiumTier` rawValue) only breaks down the local counter key, not the signpost taxonomy.

D7 Retention, Conversion, and Revenue are **not** tracked here — they come from App Store Connect Analytics / StoreKit 2 directly, per `MARKETING.md` §7 and `LAUNCH_CHECKLIST.md`.

Current log sites: `PhotoStackViewModel` (`keepPhoto`/`deletePhoto`/`snoozePhoto`/`undoLastAction`/`activateShuffle`/`emptyTrash`), `SmartFiltersView.filterRow` (tap), `PaywallView.onAppear`, `PremiumManager.purchase` (success).

---

## Conventions & Patterns

### Naming
- Views → `*View.swift`
- Services → `*Service.swift` (singletons)
- ViewModels → `*ViewModel.swift` (`@MainActor` classes)
- Extensions → `TypeName+Extensions.swift`

### Localization
Always use `String(localized: "key")` — never raw string literals for user-facing text. Keys live in `Localizable.xcstrings`. Example keys: `"filter.screenshots"`, `"meter.space_saved"`, `"victory.title"`.

**System permission strings** (`Info.plist` usage-description keys, e.g. `NSPhotoLibraryUsageDescription`) are localized separately, via `Swipy/InfoPlist.xcstrings` (same String Catalog format as `Localizable.xcstrings`) — add new locales/keys there. The `INFOPLIST_KEY_*` build setting in `project.pbxproj` must still carry the matching English string: with `GENERATE_INFOPLIST_FILE = YES`, the base/development-language (`en`) Info.plist value is always sourced from the build setting, never from the catalog — `InfoPlist.xcstrings` only generates the *other* locales' `InfoPlist.strings` overrides (confirmed by blanking the build setting and rebuilding: the base key came back empty even with the catalog populated). Keep both in sync manually; there is no single source of truth here, it's an inherent limitation of mixing `GENERATE_INFOPLIST_FILE` with a String Catalog. Any new locale also needs its language added to `knownRegions` in `project.pbxproj`.

### Haptics
Use `HapticService` for all haptic feedback. Each swipe direction has its own haptic pattern — do not use `UIImpactFeedbackGenerator` directly in views.

The one exception is self-contained celebration sequences that own their own timing (e.g. `SessionSavingsBarView.triggerHapticBurst()`). See `HAPTICS.md` for the full event map.

### Error Handling
Use `try?` for `PHPhotoLibrary.performChanges` (silent failure is acceptable — user can retry). Only throw/catch at service boundaries, not in ViewModels.

### Commit & Push Policy
**Never commit or push without explicitly asking the user for approval first.** Always show the diff or summarize the changes and wait for a green light. This applies to every commit, regardless of how small or "obvious" the change seems.

**Before every commit:** check whether any `.md` file needs updating to reflect the change. Update the relevant doc in the same commit — never ship code that is out of sync with its documentation.

### Code Quality Standard
Every code change must be **senior-level**: efficient, sharp, and precise. No over-engineering, no padding, no defensive code for scenarios that can't occur. Each change should do exactly what is needed — no more, no less.

### Documentation Hygiene
After every code change, check whether any `.md` file needs updating. The architecture docs (`OFFLINE_MODE.md`, `SNOOZE_FEATURE.md`, `ARCHITECTURE_SWIPE_LOADING.md`, `NOTIFICATIONS.md`, `CLAUDE.md`) must stay in sync with the code. If a function signature, behavior, or invariant changes — update the relevant doc in the same commit.

### Comments
The codebase is **bilingual — Hebrew + English** comments are both present and acceptable. Match the language of the surrounding code section.

### No External Dependencies
This project uses **zero third-party packages** (no CocoaPods, SPM, Carthage). Use only Apple frameworks. If you need a utility, write it inline or add to `Extensions/`.

---

## Key Behavioral Constraints

- **Undo**: Triggered either by the shake gesture or by tapping the dedicated Undo button (below the Shuffle capsule, `arrow.uturn.backward`) — both call the same `performUndo()` in `SwipeStackView`, so there is one deterministic pipeline regardless of trigger. `performUndo()` owns the guard checks (`!isDragging`, `!isPinching`) and the `viewModel.undoLastAction()` call, then hands the actual re-entry animation off to `CardStackView` via a `pendingUndoRequest` value (see "Swipe Gesture Performance" under Performance Rules for why the animation itself had to move down there, and for a reverted attempt at making this a single synchronous function — reverted after an on-device drag-smoothness regression report, not because a flaw was found in the approach itself). The undo item must always be kept in NSCache — never evict it until a new swipe occurs. The restored card re-enters with a reverse animation — off-screen from the same edge and tilt the original swipe exited through, then an underdamped spring (`response: 0.45, dampingFraction: 0.75`) carries it back to center with a slight overshoot ("deck-landing" feel). The drag gesture is blocked (`isUndoAnimating`) for the duration so a finger grabbing the card mid-flight can't fight the spring. See `ARCHITECTURE_SWIPE_LOADING.md` §6 for the full sequence.
  The FAB row's visibility conditions are intentionally split: `shuffleCapsule` is hidden while `viewModel.isOfflineMode` (shuffle and offline are mutually exclusive — see Shuffle Controls below), but `undoButton` has no such dependency and stays visible under the same `isLoading || !photoStack.isEmpty` condition regardless of offline mode — undo is purely local state (NSCache + photoStack + reviewBin) with no network involvement, so hiding it offline would remove a user's only discoverable way to recover from a mis-swipe (shake-to-undo still works but isn't self-evident).
  Only a single step of undo is supported: `PhotoStackViewModel.canUndo` (`@Published`, mirrors `lastAction != nil` via a `didSet`) drives the button's enabled/disabled and dimmed (`opacity(0.7)`) state, and is invalidated (`invalidatePendingUndo()`) whenever the stack is wholesale-replaced — filter change, shuffle toggle, or offline-mode toggle — so a stale undo can never target the wrong stack context.
  `CardStackView.dragGesture.onEnded` calls `viewModel.beginSwipe(item:action:)` **synchronously**, before the ~300ms exit-fly delay that precedes the actual `keepPhoto`/`deletePhoto`/`snoozePhoto` mutation — this sets `lastAction`/`canUndo` immediately so a shake or Undo tap during that window always targets the card just swiped, never a stale previous one. The deferred mutation itself runs through `finalizeSwipe(item:action:)`, which no-ops (returns `false`) if `undoLastAction()` already cancelled that pending swipe — the caller then skips resetting `dragOffset`/calling `onSwipeFinalized` (which is what drives the delete-particle burst and shake-hint tutorial counting up in `SwipeStackView`), since those now belong to the undo's own landing animation. See `ARCHITECTURE_SWIPE_LOADING.md` §6 ("Pending Swipe") for the full sequence.
- **Shuffle Controls**: The Shuffle toggle and "Exit Shuffle" (`xmark`) buttons live together in one glassmorphic `Capsule` (`shuffleCapsule` in `SwipeStackView.swift`) that expands to show the exit button only while shuffle is active, with an animated border — subtle white stroke when inactive, an animated neon `AngularGradient` (using the shuffle accent colors, see Color Palette) when active. Both buttons share the capsule's single `.ultraThinMaterial` background rather than each having their own, to avoid blur-on-blur.
- **Review Bin**: Items are moved here on delete swipe. No photo is permanently deleted until the user confirms "Empty Trash" in the Review Bin. On every cold start, `restoreBinFromDisk()` reconciles `reviewBinIDs` against PHPhotoLibrary — IDs with no matching asset (deleted externally via Photos.app, or app crashed mid-`emptyTrash`) are silently dropped and the clean state is flushed to disk. This keeps the bin self-healing without any manual repair flow.
- **Snooze ("Later")**: Swipe up defers the decision — the photo is hidden from the stack and re-injected at the front after N keep/delete swipes (50 → 150 → 500, exponential backoff per item). Snoozed items are persisted in `UserDefaults` and survive force-quit; they reappear immediately on the next cold start. Snooze does **not** count against the daily swipe limit. See `SNOOZE_FEATURE.md` for full details.
- **Video safety**: Never delete a video from PHPhotoLibrary without first draining its AVPlayer from VideoPlayerPool — this prevents crashes.
- **Notification quota**: Respect the 2/day cap. Check notification cap dates from `@AppStorage` before scheduling.
- **Photos permission denied/restricted**: Never a dead end. `OnboardingView` swaps its CTA to a Settings deep link instead of re-prompting; `SwipeStackView` shows a dedicated `EmptyStateView.galleryAccessDenied` instead of `VictoryView` whenever `PHPhotoLibrary.authorizationStatus(for: .readWrite)` is `.denied`/`.restricted`. Both views observe `@Environment(\.scenePhase)` and silently re-check authorization on `.active` — if the user granted access from Settings, the app recovers automatically (advances onboarding / reloads the stack) with no extra tap.
- **Paywall (3-tier)**: `PaywallView` has two presentation sites, distinguished by a required `context: PaywallContext` (`.postOnboarding` / `.swipeLimitReached`) that drives which headline/subtitle copy renders (`paywall.title.onboarding`/`paywall.subtitle.onboarding` vs the existing random `paywall.title.a`/`.b` + `paywall.subtitle`). (1) `SwipeStackView`'s `.fullScreenCover(isPresented: $viewModel.shouldShowPaywall)` whenever a keep/delete swipe is attempted after `DailyLimitService.canSwipe(isPremium:)` returns false (120 free swipes/day + a one-time +50 share bonus) — passes `context: .swipeLimitReached`, `onDismiss: nil` (uses `@Environment(\.dismiss)`, unchanged). (2) `OnboardingView`'s `step6_Paywall` — the paywall is embedded as a 7th page in onboarding's own `currentStep` switch (not a sheet/fullScreenCover), so it slides in with the same horizontal transition as every other step; `step5_QuickWin`'s CTA animates `currentStep = 6` instead of calling `onComplete()` directly. Passes `context: .postOnboarding, onDismiss: onComplete` — since there's no actual presentation to dismiss here, `PaywallView`'s X button / purchase-success / restore-success paths all route through a `closePaywall()` helper that calls `onDismiss` when set (falls back to `dismiss()` otherwise), and `onDismiss` being `onComplete` is what actually finishes onboarding. `SplashScreenView` wraps its `hasCompletedOnboarding` swap in `withAnimation` with a matching asymmetric transition so the handoff to `ContentView` continues the same leftward slide. `PremiumManager` exposes exactly 3 fixed tiers via `PremiumTier` (`monthly`/`yearly`/`lifetime`, each with a hardcoded `productID`) and `products: [PremiumTier: Product]` — a tier missing from this dictionary means its `Product.products(for:)` fetch failed or hasn't resolved yet; its pricing card still renders (shows "—", stays tappable) but the CTA disables until it resolves. Monthly and Yearly share one subscription group (see `Swipy.storekit`) so StoreKit treats a tier switch between them as an upgrade/downgrade, not a second independent purchase; Lifetime is a separate non-consumable. `updatePremiumStatus()` branches explicitly on `transaction.productType` (`.autoRenewable` vs `.nonConsumable`) rather than inferring from a nil `expirationDate` — a non-consumable never has one, so an implicit fallback there is a latent correctness bug. The headline (`paywall.title.a`/`.b`) is chosen via a `Bool.random()` `@State` initial value, and the default-selected tier (`.yearly`) is likewise a plain `@State` initial value — both decided before `body` first renders so there's no post-layout flash. Pricing cards render in `pricingRow`, a horizontally-scrolling `ScrollView` (`.scrollTargetBehavior(.viewAligned)`, edge-to-edge via a negative-padding bleed) of fixed 148×148 `PricingCardView`s — the yearly card carries a "Popular" badge (`paywall.tier.bestValue`), truncation-proofed with `.lineLimit(1)`/`.minimumScaleFactor(0.7)`. `shareButton` and `restoreButton` both live in the main scrollable content below the pricing row (restore always renders; share only when `!dailyLimit.hasSharedToday`) — only the primary purchase CTA and its error/double-billing text stay pinned via `.safeAreaInset(edge: .bottom)`. Local StoreKit testing uses `Swipy.storekit` (repo root), wired into the scheme's `LaunchAction` via a path relative to the `.xcscheme` file itself — no ASC sandbox needed to test purchase/restore/crossgrade/expiry flows in the simulator.

**Cold-start entitlement race (fixed):** In Production (not reproducible in TestFlight's Sandbox, which resolves near-instantly from a warm local receipt cache), `Transaction.currentEntitlements` performs real async JWS verification that can take 500ms-1s+ on a cold launch. `isPremium` used to default `false` and only flip after that resolved, and `PremiumManager.shared` was never touched until the first `canSwipe`/`PaywallView` access — meaning for a force-quit-then-relaunch user, the singleton's async `Task { loadProducts(); updatePremiumStatus() }` might not even start until the user's first swipe gesture itself called `canSwipe`. A premium user who had already exhausted their `swipesUsedToday` counter on a previous session (that counter still increments for premium users via `recordSwipe()`, even though `canSwipe` never blocks them, since `DailyLimitService` doesn't special-case premium there) would land back on a `hasReachedLimit == true` state, and a fast swipe during the unresolved window read `isPremium == false` — incorrectly showing the paywall (which then sometimes self-corrected via `PaywallView`'s existing `.onChange(of: premiumManager.isPremium) { if isPremium { closePaywall() } }` once resolution landed, producing a visible flash-then-dismiss rather than a permanent block).

Fixed with three changes, in order of how much of the race each closes:
1. **Synchronous local cache** — `PersistenceService.cachedIsPremium` (`@AppStorage`, mirrors the pattern of every other field there) is written every time `updatePremiumStatus()` computes a fresh value, in either direction, so an expired/refunded/revoked entitlement self-heals within one async cycle rather than staying stuck cached-true. `PremiumManager.isPremium`'s `@Published` initial value is seeded synchronously from this cache (`= PersistenceService.shared.cachedIsPremium`) — set before `init()`'s async `Task` even runs, so a *returning* subscriber reads `true` on frame 0, closing the race entirely for the common case. Deliberately `UserDefaults`-backed, not Keychain — this is an anti-flicker UX cache, not a security boundary; StoreKit's own JWS verification remains the actual source of truth downstream.
2. **Eager warm-up** — `AppDelegate.didFinishLaunchingWithOptions` now touches `PremiumManager.shared` synchronously (`_ = PremiumManager.shared`), alongside the other launch-time setup already there. This starts the async entitlement resolution racing the whole launch pipeline (Photos permission check, initial stack load) instead of racing the user's first gesture.
3. **Presentation guard for the one remaining gap** — a fresh install/reinstall right after purchase, before this process has ever completed a single `updatePremiumStatus()` pass, still has no cached value to seed from. `PremiumManager.hasResolvedEntitlements` (`@Published`, flips `true` at the end of the first `updatePremiumStatus()` call) lets `PhotoStackViewModel.shouldBlockSwipeForPaywall` (`!canSwipe && hasResolvedEntitlements`) distinguish "confirmed not premium" from "not resolved yet." `CardStackView`'s swipe-block check (`dragGesture.onEnded`) and `scheduleSwipeLimitResetIfNeeded()` both gate on this instead of raw `canSwipe`/`isPremium` — during the narrow unresolved window the swipe is let through un-blocked rather than triggering the paywall; `canSwipe` is re-evaluated fresh on the very next swipe, by which point resolution (kicked off at launch per #2) has virtually always completed. This is deliberately synchronous-only — no `Task`/`await` was added inside `dragGesture.onEnded`, which is a heavily perf-tuned hot path (see "Swipe Gesture Performance" above); the guard is a plain computed-property read, same cost class as the `canSwipe` check it replaces.

**`hasResolvedEntitlements` timing bug (fixed):** A code-review pass caught that #3's "virtually always completed" claim didn't hold — `PremiumManager.init()`'s `Task` used to `await loadProducts()` *then* `await updatePremiumStatus()` sequentially, so `hasResolvedEntitlements` (set inside `updatePremiumStatus()`) was gated behind the StoreKit product-catalog network fetch finishing too, not just entitlement verification. On a slow/flaky network, `loadProducts()` can take far longer than the assumed ~500ms-1s, during which `shouldBlockSwipeForPaywall` is `false` for *every* user regardless of premium status — a genuinely non-premium, limit-exhausted user could swipe unblocked for the full duration of that fetch. Fixed by running both concurrently (`async let products = loadProducts(); async let status = updatePremiumStatus(); _ = await (products, status)`) — they're logically independent operations with no reason to serialize, so `hasResolvedEntitlements` now only depends on entitlement verification's own latency.

---

## What to Build Toward

- Faster first-launch experience (proactively fill NSCache on app open, not just after first swipe)
- Real-time library observation (PHPhotoLibraryChangeObserver) to detect new bursts while the app is backgrounded
- Smart Filters UI: replace shimmer with skeleton loaders during Phase 2
- Low Power Mode detection: gracefully degrade background scanning (skip Phase 2, skip video pre-warming)
- **Landscape support**: the app is currently locked to Portrait only (`INFOPLIST_KEY_UISupportedInterfaceOrientations_iPhone`/`_iPad` in `project.pbxproj`, both Debug and Release) — an intentional design choice, not an oversight. The card stack, FAB layout, and gesture math throughout `SwipeStackView`/`PhotoCardView` assume a portrait aspect ratio and haven't been built or tested for landscape. Revisit only as a deliberate future feature, with layout work across the swipe stack, filters grid, and review bin grid.
  Because `TARGETED_DEVICE_FAMILY = "1,2"` makes this a universal (iPhone + iPad) build, locking to Portrait-only on iPad requires `INFOPLIST_KEY_UIRequiresFullScreen = YES` in both configs — Apple rejects App Store Connect uploads otherwise ("orientations were provided... but you need to include all... orientations to support iPad multitasking"), since iPad apps must support all 4 orientations unless they opt out of Split View/Slide Over multitasking via this flag.
- **Gallery Share Extension — jump to context**: let a user who's browsing an old photo in the native Photos app (e.g. from 01/01/2024, while the app is at 2026) tap the native Share Sheet, pick Swipy, and land directly in `SwipeStackView` with the stack starting at that photo's chronological position — instead of always starting from the default queue.
  - New **Share Extension** target reads the shared item's `PHAsset.localIdentifier` and `creationDate` via the Photos framework.
  - Deep link via custom URL scheme (`swipy://swipe?assetId=<localIdentifier>` or `?startDate=<timestamp>`), following the same pattern already used for notifications: extension posts the payload → `NotificationDelegate`-style handling → `NotificationCenter.default.post(name: .notificationNavigate)` → `ContentView .onReceive` sets `selectedTab = 1`.
  - `PhotoStackViewModel` intercepts the payload and rebuilds `photoStack` anchored at the target asset's `creationDate` (sorted fetch, same as `loadPhotos(filter:)` but seeded with a start anchor instead of a `FilterCategory`), then pages forward 30 at a time per the existing pagination rules.
  - Photos permission must already be authorized for the extension to resolve the asset — if not, fall back to opening the app at the default queue rather than a dead end (same philosophy as the existing permission-denied handling).

### Future Optimization Opportunities

- **Scope `PhotoStackViewModel`'s `@Published` surface for `CardStackView`.** The `item.fileSize`-in-Equatable regression (see "Swipe Gesture Performance" → Round 4) was caused by a specific expensive field, but the fix only capped cost-per-comparison — it didn't touch *why* the comparison runs as often as it does. `CardStackView.body`'s `ForEach` re-runs whenever `viewModel` publishes **any** `@Published` change (22+ distinct properties — `categoryCounts`, `onboardingPhotoCount`, `isShowingShareSheet`, `totalSpaceSaved`, etc. — most unrelated to card rendering), because `ObservableObject` invalidation is per-object, not per-property, and several of those properties (image/score loading) publish continuously during active swiping. A future field added to `PhotoCardView.Equatable`, even one that's individually cheap, is running inside a comparison that can fire many times per second. Deliberately not addressed now — 20% CPU during drag is already a large win over the 125-130% starting point, and splitting the ViewModel (or adding a narrower, card-specific `ObservableObject`) is a real architectural change with its own risk; not worth taking on without a concrete symptom driving it. Revisit if a similar regression resurfaces with a different field.

---

## Building the App

`xcode-select` on this machine points to CommandLineTools, not Xcode — always prefix with `DEVELOPER_DIR`:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project /Users/user/Desktop/apps/Swipy/Swipy.xcodeproj \
  -scheme Swipy \
  -destination "platform=iOS Simulator,name=iPhone 17" \
  -configuration Debug \
  build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"
```

**Known gotchas:**
- `iPhone 16` simulator doesn't exist on this machine — use `iPhone 17`
- Never use `id:...` syntax in the destination string — use `name=...`
- SourceKit errors in the editor (unknown types, missing members) are false positives from lack of project context; trust `xcodebuild` output only
- **`repeatForever` + `onAppear` inside NavigationStack/TabView**: setting a `repeatForever` animation via `onAppear` fires during the tab-switch `withAnimation` transaction, causing the ambient transaction to bleed into the repeating animation and animate layout position (not just the intended property). Fix: use `.task { try? await Task.sleep(for: .milliseconds(150)); animate = true }` to let layout settle before the animation starts.

---

## Architecture Docs

- `ARCHITECTURE_SWIPE_LOADING.md` — detailed swipe stack loading, cache lifecycle, video pre-warming, pagination strategy
- `NOTIFICATIONS.md` — notification triggers, background task setup, deep linking, known limitations
- `SNOOZE_FEATURE.md` — snooze ("Later") algorithm, exponential backoff, persistence, flush scenarios
- `HAPTICS.md` — full map of every haptic event: generators, intensities, timing, and the GB-milestone burst sequence
- `SHARE_FEATURE.md` — share architecture: UIActivityItemProvider deferral, PHAssetResourceManager.requestData, HUD lifecycle, cancellation flow
