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
              ├─ NSCache<NSString, UIImage>  # 6 images / 6MB cap
              └─ VideoPlayerPool   # singleton, max 3 AVPlayers
```

**State flows down, events flow up** through the ViewModel. Views only read `@EnvironmentObject var vm: PhotoStackViewModel` — they never touch services directly.

**Threading rules:**
- `PhotoStackViewModel` is `@MainActor` — all `@Published` mutations happen on main thread.
- Heavy work (blur detection, burst analysis, category counting) runs in `Task.detached(priority: .userInitiated)` or `withTaskGroup`, then publishes to main.
- Use `await MainActor.run { }` when pushing results from background tasks to the ViewModel.
- Never use `DispatchQueue.main.async` for new code — use `await MainActor.run` instead.

---

## File Structure

```
Swipy/
├── SwipyApp.swift              # Entry point + AppDelegate
├── ContentView.swift           # Root: onboarding gate → 3-tab layout
├── BlurDetector.swift          # CILaplacian variance on 200×200 thumb
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
│       ├── GlassmorphicTabBar.swift    # Custom bottom bar (not UITabBar)
│       ├── DopamineMeter.swift         # Space saved + item count badge
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
.ultraThinMaterial + white overlay (glassmorphism)
```

### Gradients
- Use `LinearGradient` for backgrounds and overlays
- Use `AngularGradient` only for the selected tab glow (iridescent effect)
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

ContentView: TabView(selection: $selectedTab)
    Tab 0 — SmartFiltersView
        └── tap category → loadPhotos(filter:) → selectedTab = 1
    Tab 1 — SwipeStackView    (main experience)
    Tab 2 — ReviewBinView
        └── tap item → fullScreenCover → FullScreenMediaView

Deep linking:
    NotificationDelegate → NotificationCenter.default.post(name: .notificationNavigate)
    ContentView .onReceive → selectedTab = payload
```

No `NavigationStack` or `NavigationView` is used at the root level. Tab switching is the primary navigation. `fullScreenCover` is used for full-screen media preview only.

---

## Pagination & Image Loading

- **Initial load**: 50 items (200 for blurry, 500 for burst — needed for VNFeaturePrint chain analysis)
- **Page size**: 30 items per subsequent page
- **Watermark**: next page loads when ≤ 12 items remain in `photoStack`
- **PHFetchResult** is treated as a lazy index — never fully enumerate it
- **NSCache**: `countLimit = 8`, `totalCostLimit = 8MB`; entries keyed by asset `localIdentifier`
- **Precaching**: After each swipe, top-5 images are loaded into NSCache via `precacheNextImages()`
- **VideoPlayerPool**: max 3 `AVPlayer` instances; FIFO eviction; always drain before deleting assets

---

## Smart Filter Counting (2-Phase)

Phase 1 (fast, runs first): metadata-only `PHFetchRequest` counts — instant.
Phase 2 (accurate, background): resource inspection for large videos / burst analysis — streams results.

Views show a shimmer/loading indicator while Phase 2 is in progress. Never block Phase 1 counts waiting for Phase 2 to finish.

---

## Performance Rules

1. **Never enumerate full PHFetchResult** — use index-based access only.
2. **Blur detection input**: Always downsample to 200×200 before running CILaplacian.
3. **Concurrent counting**: Use `withTaskGroup` for parallel category counts.
4. **Video pool drain**: Call `VideoPlayerPool.drain(for: assetID)` before any PHPhotoLibrary deletion.
5. **Cache eviction**: Keep only top-5 stack images + the undo item in NSCache; evict everything else.
6. **Background tasks**: All heavy computation must be in `Task.detached` or `withTaskGroup`; results published via `await MainActor.run`.
7. **Streaming results**: Blurry/burst detection must stream one-by-one into the stack — do not wait for full batch.

---

## Persistence

`PersistenceService` wraps `UserDefaults`. Keys to know:
- `hasCompletedOnboarding` — Bool, gates onboarding
- `keptPhotoIDs` — Set of kept asset local identifiers
- `reviewBinIDs` — array of bin asset local identifiers
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

### Error Handling
Use `try?` for `PHPhotoLibrary.performChanges` (silent failure is acceptable — user can retry). Only throw/catch at service boundaries, not in ViewModels.

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

---

## Architecture Docs

- `ARCHITECTURE_SWIPE_LOADING.md` — detailed swipe stack loading, cache lifecycle, video pre-warming, pagination strategy
- `NOTIFICATIONS.md` — notification triggers, background task setup, deep linking, known limitations
- `SNOOZE_FEATURE.md` — snooze ("Later") algorithm, exponential backoff, persistence, flush scenarios
