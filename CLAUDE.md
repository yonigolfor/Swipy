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
              ├─ NSCache<NSString, UIImage>  # 8 images / 8MB cap
              ├─ AestheticScoringService     # singleton — persona + score cache
              └─ VideoPlayerPool   # singleton, max 3 AVPlayers
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
│   │   ├── SwipeStackView.swift    # 3-card Z-stack + drag gesture
│   │   ├── PhotoCardView.swift     # Image or video card (mute, progress)
│   │   ├── SplashScreenView.swift  # Launch + onboarding router
│   │   └── OnboardingView.swift    # 5-step onboarding
│   ├── Filters/
│   │   └── SmartFiltersView.swift  # 6 categories + 2-phase counts
│   ├── ReviewBin/
│   │   ├── ReviewBinView.swift     # 3-column grid
│   │   ├── ReviewGridItemView.swift
│   │   └── FullScreenMediaView.swift
│   └── Components/
│       ├── SessionSavingsBarView.swift # Gamified top bar: MB progress + lava-star + GB milestone celebration
│       ├── LifetimeSavingsView.swift
│       ├── SwipeIndicator.swift
│       ├── VictoryView.swift           # Empty state celebration
│       ├── TrashCelebrationView.swift
│       ├── ParticleExplosionView.swift
│       ├── EmptyStateView.swift
│       └── VideoProgressBar.swift
│
├── Services/
│   ├── PhotoLibraryService.swift   # PHPhotoLibrary access + pagination
│   ├── AestheticScoringService.swift # Builds UserAestheticPersona from Favorites; scores cards 1–10
│   ├── PersistenceService.swift    # UserDefaults (kept IDs, bin IDs, space saved)
│   ├── HapticService.swift         # UIImpactFeedbackGenerator wrapper
│   ├── AudioSessionManager.swift   # AVAudioSession — muted video mixes with background audio
│   ├── VideoPlayerPool.swift       # Singleton AVPlayer pool (max 3)
│   ├── NotificationManager.swift   # UNUserNotificationCenter builder
│   ├── NotificationScheduler.swift # 4 trigger types + 2/day quota
│   └── NotificationDelegate.swift  # In-app notification handling
│
├── Extensions/
│   ├── View+Extensions.swift       # cardShadow, onShake, color helpers
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

The tab bar is the native iOS `TabView` — on iOS 18 it renders automatically as the floating capsule style (as in WhatsApp / Instagram). Content views stop above the tab bar via the safe area injected by `TabView`; no manual height math needed.

---

## Pagination & Image Loading

- **Initial load**: 50 items (200 for blurry, 500 for burst — needed for VNFeaturePrint chain analysis)
- **Page size**: 30 items per subsequent page
- **Watermark**: next page loads when ≤ 12 items remain in `photoStack`
- **PHFetchResult** is treated as a lazy index — never fully enumerate it
- **NSCache**: `countLimit = 8`, `totalCostLimit = 8MB`; entries keyed by asset `localIdentifier`
- **Precaching**: After each swipe, top-5 images are loaded into NSCache via `precacheNextImages()`
- **VideoPlayerPool**: max 3 `AVPlayer` instances; stale eviction via `warmUp()`; players are **paused (not released)** on tab switch so video resumes instantly on return; `drainAll()` only before PHPhotoLibrary deletion

---

## Smart Filter Counting (2-Phase)

Phase 1 (fast, runs first): metadata-only `PHFetchRequest` counts — instant.
Phase 2 (accurate, background): resource inspection for large videos / burst analysis — streams results.

Views show a shimmer/loading indicator while Phase 2 is in progress. Never block Phase 1 counts waiting for Phase 2 to finish.

---

## Performance Rules

1. **Never enumerate full PHFetchResult** — use index-based access only.
2. **Blur detection input**: Always downsample to 200×200 before running `CIEdges` (`CILaplacian` is macOS-only and returns nil on iOS).
3. **Scoring input**: Downscale to 299×299 before `VNClassifyImageRequest` — full-resolution images (1080p+) make Vision take 10+ seconds per frame.
4. **Concurrent counting**: Use `withTaskGroup` for parallel category counts.
5. **Video pool drain**: Call `VideoPlayerPool.shared.drainAll()` before any PHPhotoLibrary deletion. On tab switch use `pauseAll()` — never `release()` from `onDisappear`, or the pool will be cold on return.
6. **Cache eviction**: Keep only top-5 stack images + the undo item in NSCache; evict everything else.
7. **Background tasks**: All heavy computation must be in `Task.detached` or `withTaskGroup`; results published via `await MainActor.run`.
8. **Streaming results**: Blurry/burst detection must stream one-by-one into the stack — do not wait for full batch.
9. **Animation bleed**: Never wrap `@Published` set insertions in `withAnimation` at the ViewModel level — the ambient transaction bleeds into the card stack and causes cards to animate from wrong positions. Instead, use `.animation(_:value:)` on the specific view subtree that should animate.

---

## Persistence

`PersistenceService` wraps `UserDefaults`. Keys to know:
- `hasCompletedOnboarding` — Bool, gates onboarding
- `keptPhotoIDs` — Set of kept asset local identifiers
- `reviewBinIDs` — array of bin asset local identifiers
- `reviewBinFileSizes` — `[localIdentifier: Int64]` map of frozen file sizes captured at delete time; source of truth for space accounting (avoids iCloud-sync drift)
- `reviewBinSpaceSaved` / `totalSpaceSavedLifetime` — space saved in bytes
- `snoozedPhotos` — `[localIdentifier: snoozeCount]`, drives exponential backoff on re-injection

Notification scheduling caps at **2 notifications/day**. The 4 trigger types are: review bin reminder (24h), photo burst (50+ new photos), milestone (per GB freed), weekly cleanup.

---

## Conventions & Patterns

### Naming
- Views → `*View.swift`
- Services → `*Service.swift` (singletons)
- ViewModels → `*ViewModel.swift` (`@MainActor` classes)
- Extensions → `TypeName+Extensions.swift`

### Localization
Always use `String(localized: "key")` — never raw string literals for user-facing text. Keys live in `Localizable.xcstrings`. Example keys: `"filter.screenshots"`, `"meter.space_saved"`, `"victory.title"`.

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

- **Undo**: Shake gesture triggers undo of last swipe. The undo item must always be kept in NSCache — never evict it until a new swipe occurs.
- **Review Bin**: Items are moved here on delete swipe. No photo is permanently deleted until the user confirms "Empty Trash" in the Review Bin.
- **Snooze ("Later")**: Swipe up defers the decision — the photo is hidden from the stack and re-injected at the front after N keep/delete swipes (50 → 150 → 500, exponential backoff per item). Snoozed items are persisted in `UserDefaults` and survive force-quit; they reappear immediately on the next cold start. Snooze does **not** count against the daily swipe limit. See `SNOOZE_FEATURE.md` for full details.
- **Video safety**: Never delete a video from PHPhotoLibrary without first draining its AVPlayer from VideoPlayerPool — this prevents crashes.
- **Notification quota**: Respect the 2/day cap. Check notification cap dates from `@AppStorage` before scheduling.

---

## What to Build Toward

- Faster first-launch experience (proactively fill NSCache on app open, not just after first swipe)
- Real-time library observation (PHPhotoLibraryChangeObserver) to detect new bursts while the app is backgrounded
- Smart Filters UI: replace shimmer with skeleton loaders during Phase 2
- Low Power Mode detection: gracefully degrade background scanning (skip Phase 2, skip video pre-warming)

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
