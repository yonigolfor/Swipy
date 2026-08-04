# Senior Android Product Engineer — Manifest

**Role:** Senior Android Product Engineer building Jetpack Compose apps at Material/Big-Tech UX quality. The guiding principles are absolute smoothness (90/120Hz), compact code, and zero reinventing the wheel.

## Iron Principles (apply before writing a single line of code)

**Native First — Do Not Over-Engineer:**
Before reaching for manual layout math, custom `Canvas` drawing, or hand-rolled animation drivers — stop and ask: "How did Google implement this in their own apps (Photos, Files)? Which built-in Compose component or Modifier gives me this out of the box?"

**Leverage OS Mechanisms:**
Always prefer simple composition of system components (`LazyColumn`/`LazyGrid`, `AnimatedContent`, `Modifier.graphicsLayer`, `WindowInsets`) over third-party solutions or complex imperative code. Platform code is more efficient, better memory-managed, and future-proof against Android/AGP updates.

**Measure Before Optimizing (YAGNI):**
Do not add caching layers or complex optimizations (e.g. a hand-rolled bitmap pool where Coil already pools) unless the Layout Inspector / Macrobenchmark / Perfetto trace has proven a real need. Clean, simple code is fast code.

For every new task, ensure the proposed solution rests on these principles and presents the shortest, most elegant, most native path.

---

# Swipy (Android) — Developer Guide

## What This App Is

**Swipy** is a native Android photo/video management app with the tagline *"Declutter your memories."* It presents the device's media library as a swipe-based card stack (Tinder-style). Swipe right = keep, swipe left = delete (moves to Review Bin), swipe up = snooze ("Later" — defers the decision, re-injects into the stack after N swipes). The app also auto-identifies junk photos (blurry, screenshots, large videos, burst duplicates, screen recordings) and surfaces them via Smart Filters. Items accumulate in a Review Bin before permanent deletion, giving users an undo safety net.

This is a **feature-parity port** of the iOS app (see the root `CLAUDE.md`). Product behavior, copy, thresholds, and edge-case handling should match iOS unless a platform constraint forces a difference — always check the iOS doc first when in doubt about *what* to build; this doc governs *how* to build it on Android.

**App Icon:** Blue gradient background, white "S" letter (shared brand asset).

---

## Architecture

**Pattern:** MVI (Model-View-Intent) layered on Clean Architecture boundaries, with strict Unidirectional Data Flow. This is the Android-idiomatic analogue of the iOS app's MVVM-with-single-source-of-truth `PhotoStackViewModel` — same philosophy (state flows down, events flow up, one owner of truth per screen), expressed with `StateFlow`/`sealed class` intents instead of `@Published`/direct method calls.

```
data layer (MediaStore, DataStore, Room-free — see Data Management & Storage)
    └─ repository layer (interfaces in :domain, impls in :data)
         └─ use cases / interactors (:domain)  — one class, one verb: KeepPhotoUseCase, DeletePhotoUseCase, SnoozePhotoUseCase
              └─ PhotoStackViewModel (:feature:swipe)  — androidx.lifecycle.ViewModel
                   ├─ StateFlow<PhotoStackUiState>       — single immutable state object, single source of truth
                   ├─ Channel<PhotoStackEffect>          — one-shot events (haptics, navigation, snackbars) — NEVER model as state
                   ├─ fun onIntent(intent: PhotoStackIntent)  — the only public entry point views call
                   ├─ AestheticScoringRepository  — persona + score cache (analogue of AestheticScoringService)
                   └─ VideoPlayerPool            — singleton, bounded pool of ExoPlayer instances (max 3)
```

**Why MVI over plain MVVM-with-mutable-state:** Compose recomposition is driven by state reads, and a `ViewModel` with many independent `mutableStateOf`/`MutableStateFlow` properties (the naive Compose default) reproduces the exact bug class the iOS app spent multiple rounds fixing — see "Gesture Engine & Card Stack Performance" below. A **single immutable `UiState` data class** collected via `collectAsStateWithLifecycle()` gives you one clear diffing boundary and makes "what changed" auditable in code review. Continuous per-frame gesture values (drag offset, rotation) are the deliberate exception — see below, they must **never** live in `UiState`.

**State flows down, events flow up:**
- Composables read `val state by viewModel.uiState.collectAsStateWithLifecycle()` and render. They never touch repositories/`MediaStore` directly.
- User actions call `viewModel.onIntent(PhotoStackIntent.SwipeCard(item, direction))` — never mutate state from a Composable.
- One-shot effects (haptic burst, navigate to paywall, show snackbar) are delivered via a `Channel<Effect>` consumed with `LaunchedEffect(Unit) { viewModel.effects.collect { ... } }` — modeling these as state (e.g. a `showPaywall: Boolean` that must be manually reset) is the #1 source of "event replayed on rotation" bugs and is banned in this codebase.

**Threading rules:**
- `ViewModel`s launch work in `viewModelScope`. Anything touching `MediaStore`, `ContentResolver`, disk I/O, or `BitmapFactory` decoding runs on `Dispatchers.IO`; CPU-bound analysis (blur variance, feature-vector distance) runs on `Dispatchers.Default`.
- **Never** call `contentResolver.query()`, `openInputStream()`, or any `MediaStore` cursor operation from `Dispatchers.Main` — it is a synchronous binder/disk call and will jank or ANR.
- Use `flowOn(Dispatchers.IO)` at the repository boundary so use cases and ViewModels stay dispatcher-agnostic; a repository's public suspend/Flow API should already be main-safe, matching the iOS rule that ViewModels never talk to `PHImageManager` directly.
- Bridge legacy/blocking callback APIs (some OEM `MediaStore` quirks, `MediaMetadataRetriever`) with `suspendCancellableCoroutine`, always wiring `invokeOnCancellation` to release native resources (cursors, retrievers) — the direct analogue of the iOS rule to bridge synchronous `PHImageManager`/Vision calls off the cooperative thread pool.

---

## Project Architecture & Directory Layout

Multi-module Gradle project — module boundaries enforce the dependency direction (`:app` → `:feature:*` → `:domain` → `:data`; `:domain` has zero Android SDK dependency so use cases are unit-testable on the JVM without Robolectric).

```
swipy-android/
├── app/                                   # Application class, NavHost graph, DI graph root, manifest merge
│   └── src/main/java/com/swipy/app/
│       ├── SwipyApplication.kt            # @HiltAndroidApp
│       ├── MainActivity.kt                # Single-Activity host, edge-to-edge, splash screen (SplashScreen API)
│       └── navigation/SwipyNavHost.kt     # NavHost — 3 top-level destinations, bottom nav (see Navigation)
│
├── core/
│   ├── designsystem/                      # Compose theme, color tokens, typography, shared components
│   │   ├── theme/Color.kt                 # Palette — mirror iOS View+Extensions.swift 1:1 (see Color Palette)
│   │   ├── theme/Type.kt
│   │   └── component/                     # SwipeIndicator, ShareHud, VictoryView equivalents
│   ├── common/                            # Result wrapper, dispatcher qualifiers, extension functions
│   └── testing/                           # Fake repositories, coroutine test rules, Compose test utils
│
├── domain/                                # Pure Kotlin module — no Android SDK import allowed
│   ├── model/                             # PhotoItem, FilterCategory, SwipeAction (sealed classes/enums)
│   ├── repository/                        # Interfaces: PhotoRepository, PhotoStateRepository, PersonaRepository
│   │                                       # (PhotoStateRepository is one interface covering kept/review-bin/
│   │                                       # snoozed state — mirrors iOS's single PersistenceService rather
│   │                                       # than splitting into a separate ReviewBinRepository; see Persistence)
│   └── usecase/                           # GetPhotoStackPageUseCase, GetCategoryCountUseCase implemented so far;
│                                           # KeepPhotoUseCase, DeletePhotoUseCase, SnoozePhotoUseCase,
│                                           # UndoLastActionUseCase, ScanBlurryBurstUseCase, RefreshCategoryCountsUseCase
│                                           # still pending — Keep/Delete need :feature-layer PendingIntent/
│                                           # createTrashRequest UI wiring (see "Deletion & Trash"), not just a
│                                           # plain suspend function, so they weren't built during the pure
│                                           # data-layer pass that built PhotoStateRepository.
│
├── data/
│   ├── mediastore/                        # MediaStore query/pagination impl of PhotoRepository (see below)
│   ├── datastore/                         # Preferences DataStore impl (UserDefaults analogue — see Persistence)
│   ├── cache/                             # Disk-backed blur/burst verdict cache (DataStore<Verdicts> proto)
│   └── vision/                            # ML Kit / on-device analysis wrappers (blur, burst, aesthetic score)
│
├── feature/
│   ├── swipe/                             # Main card-stack experience
│   │   ├── PhotoStackViewModel.kt
│   │   ├── PhotoStackUiState.kt           # Immutable state data class
│   │   ├── PhotoStackIntent.kt            # Sealed class of user intents
│   │   ├── PhotoStackEffect.kt            # Sealed class of one-shot effects
│   │   └── ui/
│   │       ├── SwipeStackScreen.kt        # Screen chrome — savings bar, FAB row, badges (analogue of SwipeStackView)
│   │       ├── CardStackLayer.kt          # Gesture-isolated card stack — see Performance section, isolated for perf
│   │       └── PhotoCardComposable.kt     # Image or video card
│   ├── filters/                           # Smart Filters screen (2-phase counts — see below)
│   ├── reviewbin/                         # Review Bin grid + full-screen media viewer
│   ├── paywall/                           # Billing/paywall screen
│   └── onboarding/
│
└── build-logic/                           # Convention plugins (build.gradle.kts composition, not copy-paste)
    └── src/main/kotlin/AndroidFeatureConventionPlugin.kt  # Applies Compose, Hilt, lint baseline uniformly
```

**Module dependency rule:** `:domain` must compile without `android.jar`. If a use case appears to need `Context`, that's a signal the Android-specific work belongs in `:data` behind a repository interface, not in `:domain`.

---

## Core Tech Stack

| Concern | Choice | Notes |
|---|---|---|
| Language | Kotlin (Coroutines, Flow, StateFlow) | `kotlinx-coroutines-android`, structured concurrency only — no `GlobalScope` |
| UI | Jetpack Compose (100% declarative, no XML/View interop except `AndroidView` for `PlayerView`) | BOM-pinned versions across all modules |
| Architecture | Clean Architecture + MVI/UDF | See Architecture above |
| DI | **Hilt** | See rationale below |
| Local media | `MediaStore` (`ContentResolver` queries), `Dispatchers.IO` | See Media & Storage |
| Image/video loading | **Coil 3** (Compose-first, Kotlin Coroutines-native, `ImageLoader` with memory+disk `Cache`) | See rationale below |
| Video playback | Media3 `ExoPlayer` (+ `PlayerView` via `AndroidView`) | Bounded pool, mirrors iOS `VideoPlayerPool` |
| On-device ML | ML Kit (on-device, no network) — Image Labeling / Face-adjacent APIs are **not** used; blur/burst/aesthetic scoring done via `RenderScript`-free custom analysis (see below) | Zero-network parity with iOS `Vision`/`CoreImage` usage |
| Local persistence | Jetpack **DataStore** (Preferences + Proto) | Replaces `UserDefaults`; see Persistence |
| Billing | Play Billing Library 7 (Kotlin coroutines KTX) | Analogue of StoreKit 2 |
| Background work | `WorkManager` | Notification scheduling, deferred prescans |
| Testing | JUnit5, Turbine (Flow testing), Compose UI Test, Robolectric (data layer only), Macrobenchmark | See Build & Testing |
| Static analysis | `ktlint`, Android Lint (custom rules for the gesture/equality guardrails below), Detekt | Enforced in CI, not just pre-commit |

**Dependency Injection — Hilt, not Koin:** Hilt is chosen over Koin because (a) it's compile-time validated (a missing binding is a build error, not a runtime crash — matches this project's zero-tolerance stance on avoidable runtime failures), (b) first-party Jetpack integration (`hiltViewModel()`, `@HiltWorker` for `WorkManager`) needs no manual wiring, (c) it composes cleanly with the multi-module boundary above via `@InstallIn(SingletonComponent::class)` / `@InstallIn(ViewModelComponent::class)`. Koin's runtime DI graph and reflection-adjacent lookup is exactly the kind of "convenient but not what the platform actually optimizes for" tradeoff the Iron Principles above tell us to avoid.

**Image loading — Coil, not Glide:** Coil is chosen because it's Kotlin-first (coroutines, not callbacks), has a native `AsyncImage` Compose composable (no `AndroidView` interop tax), and its `ImageLoader` singleton pattern maps directly onto the iOS `NSCache` + `PHImageManager` split described below. Glide remains acceptable only if a specific format (e.g. certain animated formats) is proven unsupported by Coil during implementation — default to Coil.

**Zero third-party product dependencies beyond the above infra layer** — mirroring the iOS app's "no RevenueCat/Mixpanel" stance: no third-party analytics SDK, no third-party crash reporter beyond Play Console's built-in ANR/crash reporting + Firebase Crashlytics *only if* the team explicitly opts in (not default-on). Telemetry follows the same **on-device-only counters + platform-native aggregation** philosophy as iOS `AnalyticsService` — see Analytics below.

**SDK levels — decided, not placeholders:** `minSdk = 29`, `compileSdk = 34`, `targetSdk = 34` (`gradle/libs.versions.toml`). `compileSdk`/`targetSdk` are pinned to 34 rather than a newer installed platform (35/36 were also available locally) because AGP 8.5.1 — the AGP version this project is pinned to — is only tested up to compileSdk 34; building against 35 succeeds only via an explicit `android.suppressUnsupportedCompileSdk` override, which is a real risk to opt into deliberately later (e.g. once AGP is bumped), not a default to fall into now. `minSdk = 29` is what makes the legacy pre-Scoped-Storage delete branch in "Deletion & Trash" below deletable-on-sight rather than dead code kept "just in case."

---

## Color Palette

Colors must be ported 1:1 from the iOS palette (`View+Extensions.swift` / `FilterCategory.swift`) into `core/designsystem/theme/Color.kt` as `Color` constants — this app must be visually indistinguishable from iOS modulo platform chrome (status bar, nav bar, ripple vs. highlight). Do not invent a Material-default palette; Swipy has its own brand system.

```kotlin
// core/designsystem/theme/Color.kt

// Swipe Action Colors
val SwipeGreen  = Color(0xFF33CC66)  // keep
val SwipeRed    = Color(0xFFF24D4D)  // delete
val SwipeBlue   = Color(0xFF408CF2)  // snooze ("Later")
val SwipeYellow = Color(0xFFFFCC33)  // celebration particles only

// Filter Category Colors
val FilterAll              = Color(0xFF9E9E9E) // gray
val FilterScreenshots      = Color(0xFF2196F3) // blue
val FilterScreenRecordings = Color(0xFF9C27B0) // purple
val FilterLargeVideos      = Color(0xFFFF9800) // orange
val FilterBlurryPhotos     = Color(0xFFF44336) // red
val FilterBurstPhotos      = Color(0xFF00BCD4) // cyan

// Shuffle Accent Gradient
val ShuffleAccentStart = Color(0xFF3380FF)
val ShuffleAccentEnd   = Color(0xFF8033E6)
```

- Cards use `MaterialTheme.colorScheme.surface` (respects system light/dark — the Compose analogue of `UIColor.systemBackground`), never a hardcoded surface color.
- Dark backgrounds (splash, onboarding) use the same `#1A1A1F` as iOS.
- Elevation/shadow: use `Modifier.shadow(elevation = 8.dp, ambientColor = Color.Black.copy(alpha = 0.1f))` matching the iOS `cardShadow()` 8pt/10%-opacity spec — do not default to Material's stock elevation tonal overlay, which shifts a card's rendered color instead of only shadowing it.
- Typography: brand headings use a rounded `FontFamily` (bundle a rounded variable font, e.g. an OFL-licensed equivalent to SF Rounded — do **not** ship Apple's SF Rounded, it is not licensed for Android) at `32sp` / `FontWeight.Bold`, matching the iOS `.system(size: 32, weight: .bold, design: .rounded)` spec in feel, not in literal font file.

---

## Navigation

```
SplashActivity / SplashScreen composable (Android 12+ SplashScreen API for the system splash;
Compose splash content for the branded animated portion, mirroring iOS SplashScreenView)
    ├── [first launch]    → OnboardingRoute (5 steps, same step count/copy as iOS) → set hasCompletedOnboarding = true
    └── [returning user]  → SwipyNavHost start destination

SwipyNavHost (single Activity, Compose Navigation):
    NavigationBar (Material 3, bottom nav — Android's idiomatic equivalent of the iOS floating-capsule TabView;
                    do NOT attempt to pixel-clone the iOS floating capsule — that fights Android's platform
                    conventions and gesture-nav inset handling for zero user benefit. Iron Principle: native first.)
        Destination 0 — SmartFiltersRoute
            └── tap category → viewModel.onIntent(LoadPhotos(filter)) → navController.navigate(SwipeRoute)
        Destination 1 — SwipeRoute (main experience)
            └── pinch-to-zoom on top card; bottom nav hides via a shared `bottomBarVisible` NavHost-level state
                (the Compose analogue of iOS's `.toolbar(.hidden, for: .tabBar)`)
        Destination 2 — ReviewBinRoute
            └── tap item → navigate to ReviewBinDetailRoute (full-screen, custom enter/exit transition,
                the analogue of iOS's fullScreenCover — NOT a bottom sheet, must cover status bar too)

Deep linking:
    NotificationManager → PendingIntent with a nav deep link URI (swipy://swipe?tab=1)
    SwipyNavHost registers this as a `navDeepLink` on the relevant composable destination —
    prefer this over manually observing an Intent extra in MainActivity; it's the platform-native mechanism.
```

Single-Activity architecture. Compose Navigation is the only nav framework — no Fragments, no legacy `Navigation` XML graphs. Full-screen media (Review Bin detail) is a **separate navigation destination** with a custom `enterTransition`/`exitTransition` (fade + scale from the tapped thumbnail's bounds using shared-element transitions, `SharedTransitionLayout`, API 34+ / Compose 1.7+) rather than a dialog — this matches the iOS `fullScreenCover` semantic of "genuinely new screen, not an overlay."

### Layout Direction

Android's Compose `LocalLayoutDirection` already correctly mirrors RTL languages (Hebrew) at the system level — `Modifier.offset`, `Arrangement`, and `Alignment` all respect it automatically, unlike the iOS bug this app's `CLAUDE.md` documents working around (raw `.offset(x:)` needing an explicit LTR pin). **Do not port that iOS workaround.** However: swipe *gesture direction* (finger drag left = delete) is a spatial/physical gesture, not a text-flow concept, and must stay physically left/right regardless of layout direction — explicitly read raw pointer `Offset` in `pointerInput` (which is already direction-agnostic, unlike `Alignment.Start/End`) rather than any layout-direction-aware modifier for the drag math itself.

---

## Gesture Engine & Card Stack Performance (120Hz / High Refresh Rate)

This section is the direct, hard-won port of the iOS "Swipe Gesture Performance" postmortem (root `CLAUDE.md`) — that investigation took 4 rounds to fully solve on UIKit/SwiftUI, and the underlying cause (per-frame state mutation forcing a full subtree re-diff) has an **exact** analogue in Compose recomposition. Do not rediscover this the hard way; follow the rules below from the start.

### The Core Rule: Render-Layer-Only Mutation During Active Gestures

**Zero unnecessary recompositions during an active drag/pinch.** A `DragGesture`/`pointerInput` callback can fire up to 120 times/second. If the value it writes is read by `Composable` *content* (i.e. anything that affects *what* is drawn — text, icon choice, layout size, item count), Compose must recompose that scope every frame. If instead the value is only read inside `Modifier.graphicsLayer { }`, Compose applies it during the **layout/draw phase**, skipping recomposition entirely — the same role `.visualEffect` plays on iOS (see iOS `CLAUDE.md` Round 2, item 3).

**Concretely, for `CardStackLayer.kt`:**

```kotlin
// CORRECT — offset/rotation/scale live only inside graphicsLayer's lambda.
// The lambda is re-evaluated at draw time without triggering recomposition of this Composable's body.
var dragOffsetX by remember { mutableFloatStateOf(0f) }
var dragOffsetY by remember { mutableFloatStateOf(0f) }
var dragRotationZ by remember { mutableFloatStateOf(0f) }

Box(
    modifier = Modifier
        .graphicsLayer {
            translationX = dragOffsetX
            translationY = dragOffsetY
            rotationZ = dragRotationZ
        }
        .pointerInput(item.id) {
            detectDragGestures(
                onDrag = { change, dragAmount ->
                    change.consume()
                    dragOffsetX += dragAmount.x   // written every frame — fine, ONLY graphicsLayer reads it
                    dragOffsetY += dragAmount.y
                    dragRotationZ = (dragOffsetX / 20f).coerceIn(-15f, 15f)
                },
                onDragEnd = { /* decide keep/delete/snooze, animate via Animatable, THEN commit to ViewModel */ }
            )
        }
)
```

```kotlin
// WRONG — do not do this. Reading dragOffsetX in a Text/layout-affecting position
// (or worse, hoisting it into PhotoStackUiState) forces full recomposition of every
// composable that reads state derived from this ViewModel, every single drag frame —
// this is the Compose-world version of the iOS "@State on SwipeStackView" bug that
// caused a 125-130% CPU spike, documented in the iOS CLAUDE.md.
Text("Offset: $dragOffsetX")  // fine ONLY in debug overlays gated out of release builds
```

**Never let a per-frame gesture value flow into `PhotoStackUiState` / `StateFlow`.** `StateFlow` collection via `collectAsStateWithLifecycle()` is a recomposition trigger by design — piping 120fps drag deltas through it recreates the exact anti-pattern the iOS team spent 4 rounds eliminating (continuous `@State` living on a view that also hosts expensive unrelated siblings). Gesture deltas are `remember { mutableFloatStateOf() }` **local to the Composable that owns the gesture**, full stop. Only the *rare, discrete* events matter to the ViewModel: gesture start, direction-threshold crossing (for swatching which `SwipeIndicator` to show — analogous to iOS's `swipeDirection` state, updated only `if newDirection != swipeDirection`), and gesture end (commit the swipe).

### Card Isolation — Why `CardStackLayer` Is a Separate Composable

`SwipeStackScreen` also hosts the savings bar, FAB row (shuffle capsule, undo button — each with elevation/shadow), and mode badges — all expensive-to-recompose siblings, directly mirroring why iOS extracted `CardStackView` out of `SwipeStackView`. **`CardStackLayer` must be its own Composable function**, receiving only the minimal, stable parameters it needs (`items: ImmutableList<PhotoItem>`, callbacks) — never inline the card stack's gesture-handling directly inside `SwipeStackScreen`'s body. Use `kotlinx.collections.immutable.ImmutableList` (not `List`) for the items parameter — a plain `List` is not structurally stable to the Compose compiler's stability inference, so every recomposition of the parent is treated as "list might have changed," defeating skipping even when nothing did.

### Conditional Animation — Only the Card Arriving at Index 0 Animates

Directly mirrors the iOS Round-3 postmortem (card-elevation transition bug, then the follow-up conditional-animation-on-every-index regression, then the `if/else` structural-identity regression). The same three failure modes apply to Compose and must be avoided the same way:

1. **Render every visible card (top + background) from a single `key`-stable loop**, not a structurally separate "top card" branch:
   ```kotlin
   items.forEachIndexed { index, item ->
       key(item.id) {   // stable identity across index changes — the Compose analogue of ForEach(id:)
           PhotoCardComposable(item = item, index = index, ...)
       }
   }
   ```
   Using `key(item.id)` (not array index) is what lets Compose recognize "card promoted from index 1 → 0" as the *same composition* changing its `index` parameter, rather than destroying and recreating it — exactly the iOS `.id()`/`ForEach` identity lesson. Getting this wrong reproduces the iOS bug where a promoted card kept showing the previous card's stale image because its `@State` (here: `remember` state, `AsyncImage` request) was destroyed and re-created instead of persisting.

2. **Animate `index`-derived transform only when the destination index is 0:**
   ```kotlin
   val animatedScale by animateFloatAsState(
       targetValue = targetScaleForIndex(index),
       animationSpec = if (index == 0) spring(dampingRatio = 0.85f, stiffness = 380f) else snap(),
       label = "cardScale"
   )
   ```
   `snap()` for every other index — a card moving from index 2 → 1 must jump instantly with no motion, matching the iOS fix where only the card becoming the new top card gets the spring. Animating every index's transition unconditionally reproduces the iOS "second, distracting motion nobody asked for" bug.

3. **Never gate gesture/`graphicsLayer` modifiers behind an `if (index == 0) { ... } else { ... }` structural branch** on the *card's own modifier chain**. Composable structural branches (`if`/`when` around emitting different composables) are a Compose slot-table identity boundary exactly like SwiftUI's `_ConditionalContent` — a card crossing from the `else` branch to the `if` branch on the frame it's promoted is destroy-old/create-new to Compose, silently breaking the `key()`-based identity continuity from point 1, at precisely the moment the animation is supposed to play. Apply gesture modifiers **unconditionally** to every card, gating only the *values* passed to them:
   ```kotlin
   .pointerInput(item.id, index == 0) {
       if (index == 0) detectDragGestures(...) else awaitPointerEventScope { /* absorb, no-op */ }
   }
   ```
   The one place a structural `if` is safe is a purely decorative **sibling overlay** that doesn't wrap the card itself — e.g. `if (index == 0 && isDragging) { SwipeIndicatorOverlay(...) }` as a separate `Box` layered via `Modifier.zIndex`, never as a branch around `PhotoCardComposable` itself.

### The Strict Equality / Stability Rule

**NEVER trigger a blocking `MediaStore`/`ContentResolver` query, or any I/O, inside:**
- A `data class`'s auto-generated `equals()`/`hashCode()` if that class is used as Compose state or a `key()` argument,
- A custom `remember(key1, key2) { ... }` key computation,
- A `derivedStateOf { }` block,
- Any `@Stable`/`@Immutable`-annotated class's property getters that Compose's stability inference or skip-check might invoke.

This is the direct Android port of the iOS "Round 4" postmortem: `PhotoCardView.Equatable`'s `==` calling `PHAsset.fileSize`, which silently executed a real Photos-database query (`PHAssetResource.assetResources(for:)`) inside what looked like a cheap struct comparison — invoked repeatedly per frame during active gesture handling because `ObservableObject` invalidation is per-object, not per-property, causing a measured, reported CPU/smoothness regression that took real profiling effort to trace back to an *equality check*, of all places.

**The Android equivalent trap:** `PhotoItem`'s file size, `MediaStore` row extras, or any derived Uri metadata must be resolved **once**, eagerly, at fetch time, and stored as a plain `Long`/`String` field on the `PhotoItem` data class — never computed lazily inside a getter that a `data class`'s structural `equals()` would invoke. When defining `PhotoItem`:

```kotlin
@Immutable   // tells the Compose compiler this type's public properties are safe to skip-check without re-deriving stability
data class PhotoItem(
    val id: Long,                 // MediaStore _ID — used as the key() identity, cheap Long comparison
    val uri: Uri,
    val fileSizeBytes: Long,      // resolved ONCE at fetch/pagination time via the MediaStore projection — never lazy
    val mimeType: String,
    val dateAdded: Instant,
    // ... every field here must already be a resolved, cheap-to-compare primitive/value type.
    // If a field requires a ContentResolver call to produce, resolve it in the repository
    // BEFORE constructing this object — never inside a computed property on this class.
)
```

If a future field genuinely needs an expensive per-item signal (e.g. a live "is this still on disk" check), follow the iOS postmortem's stated correct fix for the equivalent case: a `StateFlow<Set<Long>>` the repository updates only when it actually detects a real change, consumed as a lookup (`invalidIds.contains(item.id)`) — never a query embedded in equality/comparison logic itself.

**Lint enforcement:** add a custom Detekt/Lint rule (or, at minimum, a mandatory code-review checklist item — see Code Review below) that flags any `ContentResolver`, `MediaStore`, `File.length()`, or `MediaMetadataRetriever` call appearing textually inside an `equals()` override, a `hashCode()` override, or a `remember`/`derivedStateOf` lambda. This bug class has already cost real engineering time once (on iOS); it must not be independently rediscovered on Android.

### `graphicsLayer` vs. `Modifier.offset` — Always Prefer `graphicsLayer` for Gesture-Driven Values

`Modifier.offset(x, y)` with `State<Dp>` arguments participates in the **layout** pass (triggers `remeasure`), not just draw — using it for 120fps drag deltas is measurably worse than `graphicsLayer { translationX = ... }`, which only triggers `relayout`-free re-draw. This is a strictly Android-specific addendum with no direct iOS analogue (SwiftUI's `.offset()` doesn't have the same layout-pass cost), but the underlying discipline — "per-frame gesture state must resolve at the cheapest possible pipeline stage" — is identical in spirit to the `.visualEffect` lesson.

### Frame-Budget Discipline

Target frame budget is **8.3ms (120Hz)** on supported devices, degrading gracefully to **16.6ms (60Hz)** — never assume 60Hz as the baseline on a modern mid/high-tier Android device. Use `Modifier.graphicsLayer`'s `compositingStrategy = CompositingStrategy.Offscreen` (the Compose analogue of iOS `.drawingGroup()`) **only** for the same case iOS used it: flattening a static multi-layer composite (e.g. blur-background + sharp-foreground image) into one GPU texture. Do **not** apply it to the live video surface (`PlayerView` embedded via `AndroidView`) — same rationale as iOS: offscreen compositing doesn't reliably composite a live platform-native surface (`SurfaceView`/`TextureView` under `PlayerView`) the way it does a static Compose draw tree; prefer `TextureView` mode on `PlayerView` if compositing with Compose content above/below it is required, and profile before assuming it's necessary at all.

---

## Media & Storage Operations

### Permissions

Android 13+ (`API 33`, `TIRAMISU`) introduced granular media permissions — request exactly what's needed, never the legacy blanket permission on a device that supports granular:

```kotlin
val mediaPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
    listOf(Manifest.permission.READ_MEDIA_IMAGES, Manifest.permission.READ_MEDIA_VIDEO)
} else {
    listOf(Manifest.permission.READ_EXTERNAL_STORAGE)
}
```

- **Android 14+ (`API 34`, `UPSIDE_DOWN_CAKE`) partial access:** handle `READ_MEDIA_VISUAL_USER_SELECTED` — a user can grant access to a *subset* of media. Detect this via `context.checkSelfPermission(READ_MEDIA_VISUAL_USER_SELECTED) == GRANTED` alongside the full permissions being denied, and surface a persistent "manage selected photos" affordance (`Intent(MediaStore.ACTION_USER_SELECT_IMAGES_FOR_APP)`) rather than silently operating on a mysteriously small library — this has no iOS analogue (iOS's closest equivalent, limited Photos Library access, is already handled by the existing `PHPhotoLibrary.authorizationStatus` check) and is a **required** launch-blocking check for Play Store compliance on 14+.
- Mirror the iOS "never a dead end" philosophy exactly: on denial, never re-prompt in a loop — swap the CTA to a Settings deep link (`Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.fromParts("package", packageName, null))`). Re-check authorization `onResume()`/via `Lifecycle.Event.ON_RESUME` (the Android analogue of iOS's `scenePhase == .active` re-check) so a Settings-granted permission recovers automatically with no extra tap.
- Request permissions via `rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions())` — never the deprecated `requestPermissions()`/`onRequestPermissionsResult` Activity callback pair.

### `MediaStore` Querying — Pagination & Performance

- **Never** run an unbounded `contentResolver.query()` over the full media store and hold a `Cursor` open longer than the single fetch — page explicitly using `Bundle`-based query args (`ContentResolver.QUERY_ARG_LIMIT`, `QUERY_ARG_OFFSET`, `QUERY_ARG_SQL_SORT_ORDER`) on API 30+, with the `sortOrder LIMIT n OFFSET m` string fallback below 30.
- Mirror the iOS pagination constants for product parity: **initial load 50 items** (200 for blurry candidate pool, 500 for burst — same rationale, feature-vector chain analysis needs a wide candidate window), **page size 30**, **watermark at ≤15 remaining** in the in-memory stack.
- Query only the columns actually needed (`MediaStore.MediaColumns._ID`, `SIZE`, `DATE_ADDED`, `MIME_TYPE`, `WIDTH`, `HEIGHT`, `DURATION` for video) — a `SELECT *`-equivalent wide cursor is wasted binder/IPC payload on every page.
- Treat the returned `Cursor` as a **lazy, one-directional walk** — `moveToNext()` in a loop, map to `PhotoItem` immediately per row, close the cursor in a `use { }` block. Never `cursor.count` to eagerly materialize the full result set (the direct analogue of the iOS rule "PHFetchResult is a lazy index — never fully enumerate it").
- Register a `ContentObserver` on `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` / `Video`'s equivalent (the Android analogue of `PHPhotoLibraryChangeObserver`) to detect external edits/deletions (e.g. user deletes a photo from Google Photos while Swipy is backgrounded) and reconcile the Review Bin / cached verdicts — mirrors the iOS `photoLibraryDidChange` incremental-invalidation logic (only wipe caches for assets that actually changed/were removed, never a full wipe on every notification).

### Image & Video Loading

- **Coil `ImageLoader`** is configured once (Hilt `@Singleton`, provided via `@Module`) with:
  - Memory cache sized as a percentage of available app memory (`MemoryCache.Builder().maxSizePercent(context, percent = 0.25)`) — the Coil-native equivalent of the iOS `NSCache` 10-online/30-offline item-count split; prefer Coil's percent-of-heap sizing over a hardcoded item count, since Android's per-device heap ceiling varies far more than iOS's, and letting Coil's OS-aware sizing do this is the "measure before optimizing" principle in practice.
  - Disk cache (`DiskCache.Builder()`, `Dispatchers.IO`) for thumbnail persistence across cold starts.
  - `crossfade(true)` only for genuinely first-load images (mirroring iOS's careful "don't animate on cache-hit re-render" instinct) — gate crossfade off when Coil reports the result came from `MemoryCache` (`SuccessResult.dataSource == DataSource.MEMORY_CACHE`), same reasoning as the iOS `.animation(value:)` bleed rule: don't animate something that didn't visibly change.
- **Video via Media3 `ExoPlayer`, pooled** — direct Kotlin port of `VideoPlayerPool`: a bounded pool (max 3 `ExoPlayer` instances), players are **paused, not released**, on navigation away from the swipe screen so playback resumes instantly on return; `releaseAll()` only called before a `MediaStore.createDeleteRequest()` batch, mirroring the iOS "drain before delete" video-safety rule below.
- Bitmap decoding for analysis (blur variance, feature vectors) must **downsample at decode time** via `BitmapFactory.Options.inSampleSize` (or `ImageDecoder.setTargetSize` on API 28+) — never decode full-resolution then scale down in memory. Mirrors the iOS rule to downsample to 200×200 before `CIEdges` / 299×299 before `VNClassifyImageRequest`; use the same target dimensions for cross-platform threshold parity if the blur/burst/aesthetic algorithms are meant to agree between iOS and Android.

### Deletion & Trash — Scoped Storage Compliance

- **Android 11+ (`API 30`)**: use `MediaStore.createTrashRequest()` for the Review Bin's "soft delete" semantic — this is the *exact* platform-native analogue of the iOS Review Bin (items are recoverable, not gone) and should be preferred over a custom app-level trash table wherever the OS mechanism suffices. `createTrashRequest()` returns a `PendingIntent` that must be launched via `rememberLauncherForActivityResult(ActivityResultContracts.StartIntentSenderForResult())` — this is a **user-consent-gated, batchable** operation; batch the full "Empty Trash" confirmation into one `createDeleteRequest()` call rather than one syscall-adjacent request per item, both for the obvious throughput reason and because each request surfaces a system confirmation dialog.
- **Android 10 (`API 29`)**: `createTrashRequest()`/`createDeleteRequest()` don't exist yet — Scoped Storage on 29 still permits direct delete of the app's *own* media, but for foreign-app media (the common case — most gallery content wasn't created by Swipy) fall back to `MediaStore.Images.Media.EXTERNAL_CONTENT_URI` delete + catch `RecoverableSecurityException`, then launch its embedded `PendingIntent` via `startIntentSenderForResult` — this is the exact mechanism `RecoverableSecurityException` exists for.
- **Below API 29**: legacy direct `File.delete()` on the resolved file path is acceptable (pre-Scoped-Storage), gated behind `WRITE_EXTERNAL_STORAGE` — but confirm this codepath is still reachable given the app's actual `minSdk`; if `minSdk` is 29+, delete this branch and the permission entirely rather than keeping dead defensive code (Iron Principle: no defensive code for scenarios that can't occur).
- **Video safety, ported directly:** never issue a delete/trash request for a video whose `Uri` is currently loaded into a pooled `ExoPlayer` without first calling `player.stop()` / releasing that pool slot — the exact rationale as the iOS rule ("never delete a video from PHPhotoLibrary without first draining its AVPlayer from VideoPlayerPool — this prevents crashes"); on Android the failure mode is more likely a lingering `MediaCodec`/`Surface` reference than a hard crash, but the same drain-before-delete discipline applies.
- The "Empty Trash" *confirm* action maps to a single `createDeleteRequest()` covering every `Uri` currently in the Review Bin — always batch, never loop-per-item, both for correctness (avoids partial-completion states if the user backs out of the system dialog partway) and for the obvious performance reason.

---

## Persistence

Jetpack **DataStore** replaces `UserDefaults` — use **Preferences DataStore** for simple scalar/set state (direct key-value parity with the iOS keys) and consider **Proto DataStore** only if a given blob's schema would benefit from real type-safety/versioning (e.g. the blur/burst verdict cache below). Do not reach for Room/SQLite for this app's local state — there is no relational query need here, matching the iOS decision to use flat `UserDefaults` JSON blobs rather than CoreData for the equivalent state.

Keys to port 1:1 from iOS `PersistenceService`:
- `hasCompletedOnboarding` — `Boolean`
- `keptPhotoIds` — `Set<Long>` (MediaStore row IDs, not Uri strings — cheaper comparison, stable within a device)
- `reviewBinIds` — ordered list, `Set<Long>` + a separate ordering list if display order matters
- `reviewBinFileSizes` — `Map<Long, Long>` — frozen file sizes captured at trash time, same "avoid cloud-sync drift" rationale as iOS (Google Photos backup/sync is the Android analogue of iCloud drift here)
- `reviewBinSpaceSaved` / `totalSpaceSavedLifetime` — bytes
- `snoozedPhotos` — `Map<Long, Int>` snooze count, same exponential backoff schedule as iOS (50 → 150 → 500)

The disk-backed blur/burst verdict + feature-vector cache (iOS `BlurBurstCacheService`) ports as a **Proto DataStore** with the same architecture: debounced writes (coalesce writes ~2s after the last mutation — implement via a `MutableSharedFlow` + `.debounce(2.seconds)` collector in a dedicated repository-owned `CoroutineScope`, not a raw `Handler`/`Timer`), a `schemaVersion` field checked at load time to invalidate only the feature-vector blob on an analysis-algorithm change (never the cheap verdict map), and incremental invalidation driven by the `ContentObserver` from the Media & Storage section above.

---

## Smart Filter Counting (2-Phase) — Ported Architecture

Direct port of the iOS 2-phase counting design, same rationale:

- **Phase 1 (fast, first):** `MediaStore` `COUNT(*)` projection queries per category, capped at 100 (matches a "99+" display ceiling) — instant, including for `.blurryPhotos`/`.burstPhotos` where this is a *candidate-pool* estimate (non-screenshot images), not a real match count.
- **Phase 2 (accurate, background):** runs in parallel via structured concurrency (`coroutineScope { async { ... } }` for each of large-videos/blurry/burst, joined) inside a use case launched at `Dispatchers.Default` (CPU-bound) / `Dispatchers.IO` (file-size resource inspection) as appropriate. Results persist to DataStore so a warm cache is available on next launch before Phase 2 even reruns.
- `categoriesRecalculating: StateFlow<Set<FilterCategory>>` drives the dim+spinner per category — **only for a category's first-ever accurate computation**, exactly mirroring the iOS rule (`expensiveCategories.subtracting(cached.keys)`); once verified, Phase 2 reruns silently with the badge number animating via Compose's `animateContentSize()`/a custom `AnimatedContent` on the digit (the Compose analogue of `.contentTransition(.numericText())`).
- **Trigger discipline, ported exactly:** Phase 2 only fires on first-ever load this session, after an action flags a pending-update signal and the user returns to the Filters screen, or explicit pull-to-refresh (`PullToRefreshBox`) — never on a bare tab switch with no state change, and **never** unconditionally from the app's cold-start/permission-grant path. The iOS app went through three separate rounds of reintroducing a cold-start jank bug via well-intentioned "self-healing" fallback triggers that fired Phase 2 unconditionally on every launch — do not reintroduce that mistake on Android by adding a "just in case" refresh call in `MainActivity`/`SwipyApplication.onCreate()`. If a `ViewModel`-scoped "has this category ever been computed" check is `false`, that's a reason to compute it **when the user opens the Filters screen**, not a reason to eagerly compute it while the user is looking at the swipe stack.
- QoS parity: Android has no direct `qos_class` equivalent, but `Dispatchers.Default`'s thread pool is sized to `Runtime.availableProcessors()` and **will** contend with UI-thread work under sustained load the same way iOS's `.userInitiated` contended with the main thread — use `Dispatchers.Default.limitedParallelism(n)` (n=3, matching the iOS background-prescan concurrency cap) for any prescan work that runs while the user might simultaneously be dragging a card, and reserve full unthrottled `Dispatchers.Default` parallelism only for work launched while the user is actively looking at the Filters screen's own loading state (interactive-path parity with the iOS `defaultConcurrency = 6`).

---

## Analytics / Telemetry

Mirrors the iOS "native-only, on-device, no third-party SDK" stance:
- **Local aggregate counters** — a `Map<String, Int>` persisted via Preferences DataStore (JSON-encoded, same shape as iOS `analyticsEventCounts`), incremented through a single `AnalyticsService.log(event: AnalyticsEvent, detail: String? = null)` call. Counts only, no raw timestamped event log — same bounded-footprint rationale as iOS.
- **Platform-native aggregation:** use `androidx.tracing.Trace` (`Trace.beginSection`/`endSection`, or the Kotlin `trace { }` inline helper) around the same log sites, which Android Studio's **System Trace**/Perfetto and, in production, **Android Vitals**' custom trace sections can surface — the direct analogue of iOS `os_signpost` → MetricKit → Xcode Organizer. This requires no subscriber code and no third-party backend, preserving the zero-dependency telemetry stance.
- A `#if DEBUG`-equivalent (`BuildConfig.DEBUG`-gated) `AnalyticsDebugScreen` composable, reachable via a long-press on the Filters screen's "Device" section header — direct parity with the iOS `AnalyticsDebugView` gesture and gating.
- D7 retention, conversion, and revenue come from **Play Console Statistics** / Play Billing Library purchase records directly — never re-derived locally, matching the iOS stance that this class of metric belongs to the store platform, not the app's own telemetry.

---

## Code Style, Naming Conventions & Performance Guardrails

### Naming
- Composable screens → `*Screen.kt` (top-level, nav-destination-bound; e.g. `SwipeStackScreen`)
- Composable components → `*Composable`/plain descriptive name for reusable pieces (`PhotoCardComposable`, `SwipeIndicator`) — avoid the redundant `*View` suffix carried over from iOS naming; that suffix is idiomatic UIKit/SwiftUI, not idiomatic Compose.
- ViewModels → `*ViewModel.kt`, one per feature/screen, `@HiltViewModel`
- Use cases → `VerbNounUseCase.kt` (`KeepPhotoUseCase`, not `PhotoKeepUseCase`) — one class, one public `suspend operator fun invoke(...)`
- Repositories → interface in `:domain` as `*Repository`, implementation in `:data` as `*RepositoryImpl`
- Sealed classes for intents/effects/state → `PhotoStackIntent`, `PhotoStackEffect`, `PhotoStackUiState` — exhaustive `when` on intents in the ViewModel, no `else ->` catch-all branch (a new intent case must force every handler site to be updated at compile time, not silently fall through)

### Localization
Always use Android string resources (`stringResource(R.string.filter_screenshots)`) — never raw string literals for user-facing text, matching the iOS `String(localized:)` discipline. Mirror the iOS `Localizable.xcstrings` key namespace 1:1 where possible (`filter.screenshots` → `filter_screenshots`) so a translator/localization pass can reuse the same source strings across platforms.

### Compose-Specific Guardrails
- Prefer `@Immutable`/`@Stable` annotations on every model class that crosses into Compose state — an unannotated data class holding a `List<T>` (not `ImmutableList`) is treated as unstable by the compiler, silently disabling skip-recomposition for every Composable that reads it. Run the Compose Compiler Metrics report (`-P plugin:androidx.compose.compiler.plugins.kotlin:reportsDestination=...`) as part of CI and fail the build on a regression in the tracked screens' stability/skippability numbers for `feature:swipe`.
- Never pass a lambda literal defined inline inside a frequently-recomposing parent as a parameter to a child without `remember`-wrapping it, if that child is otherwise stable/skippable — an unstable lambda reference defeats the child's skip check the same way the iOS postmortem describes a freshly-allocated `onShare` closure defeating `PhotoCardView`'s `Equatable` conformance. Hoist gesture/action callbacks with `remember(key) { { ... } }` or reference a stable method value where possible.
- `LazyColumn`/`LazyVerticalGrid` (Review Bin, Smart Filters) must supply an explicit `key = { it.id }` to every `items()` call — omitting it defeats item-level recomposition scoping and animation continuity across list mutations, the direct analogue of the `ForEach(id:)` identity rule referenced throughout this doc.
- `derivedStateOf` is for values that change **less often** than their inputs (e.g. "is the drag past the swipe threshold" derived from a fast-changing offset) — using it as a general-purpose memoization tool for anything that doesn't have this "reads often, changes rarely" shape adds overhead for no benefit.

### Code Review Checklist Addendum (Android-specific)
In addition to the standard review bar, explicitly check every PR touching `feature:swipe`/`CardStackLayer` for:
1. No per-frame gesture value written into `StateFlow`/`UiState`.
2. No `ContentResolver`/`MediaStore`/`File` I/O inside `equals()`, `hashCode()`, `remember` keys, or `derivedStateOf`.
3. No structural `if`/`when` branch wrapping a card's gesture modifiers or its position in a `key()`-scoped loop.
4. Any new `PhotoItem` field is resolved eagerly at fetch time, not lazily on read.

### Error Handling
Use `runCatching { }` at repository/data-source boundaries only (mirrors the iOS `try?` scoping rule — errors are swallowed/logged at the service boundary, never left to propagate into ViewModel/UI logic as unchecked exceptions). Domain/use-case layer functions return a `Result<T>`-style sealed wrapper (`core/common`'s `AppResult<T>`) rather than throwing, so ViewModels handle failure as an explicit `when` branch, never a `try/catch` around business logic.

### Commit & Push Policy
**Never commit or push without explicitly asking the user for approval first** — this rule from the iOS `CLAUDE.md` applies identically here; it is a repository-wide policy, not an iOS-specific one. Always show the diff or summarize the changes and wait for a green light.

**Before every commit:** check whether any `.md` file (this one, or a future `ARCHITECTURE_ANDROID_*.md`) needs updating to reflect the change. Update the relevant doc in the same commit.

### Code Quality Standard
Every code change must be senior-level: efficient, sharp, and precise. No over-engineering, no padding, no defensive code for scenarios that can't occur (e.g. don't keep a below-API-29 legacy delete path alive if `minSdk` is 29+). Each change does exactly what is needed — no more, no less.

### No Unnecessary Third-Party Dependencies
Beyond the infra layer explicitly named in Core Tech Stack (Compose, Hilt, Coroutines, Coil, Media3, DataStore, Play Billing, WorkManager — all either first-party Jetpack/AndroidX or, in Coil's case, the de facto Compose-native standard), do not add a library without checking whether `androidx.*` already solves the problem. This is the direct port of the iOS "zero external dependencies" stance, adapted to acknowledge that the Android platform's "first-party" surface is broader (Jetpack is not literally the OS the way `PHPhotoLibrary`/`Vision` are, but occupies the same trust/stability tier for this project's purposes).

---

## Build & Testing Commands

```bash
# Full debug build
./gradlew :app:assembleDebug

# Install + run on a connected device/emulator
./gradlew :app:installDebug

# Unit tests (domain + data, JVM-only — no Robolectric needed in :domain)
./gradlew test

# Unit tests for a single module
./gradlew :domain:test
./gradlew :data:mediastore:test

# Instrumented / Compose UI tests (requires a connected device or emulator)
./gradlew connectedDebugAndroidTest

# Static analysis — run before every commit, matches iOS's "build must be clean" bar
./gradlew ktlintCheck detekt lint

# Compose compiler stability/skippability report (CI-gated, see Compose-Specific Guardrails above)
./gradlew :feature:swipe:assembleDebug \
  -Pandroidx.compose.compiler.plugins.kotlin.reportsDestination=build/compose_reports

# Macrobenchmark — startup + scroll/drag jank, the Android analogue of profiling the
# iOS gesture-performance regressions with Instruments; run against a release-like
# (minified, non-debuggable) build variant, never against :app:debug
./gradlew :benchmark:connectedBenchmarkAndroidTest
```

**Known gotchas:**
- The Compose Preview renderer (`@Preview`) does not execute real `pointerInput`/gesture code — verify gesture changes on a physical device or emulator, never trust Preview for anything touching `CardStackLayer`.
- `MediaStore` behavior (especially `createTrashRequest`/`createDeleteRequest` availability and `RecoverableSecurityException` handling) genuinely differs across OEM skins on API 29-30 in practice, despite matching the documented AOSP contract — test deletion flows on at least one non-Pixel OEM device/image before shipping a change to that path, not just the emulator.
- High refresh rate (90/120Hz) is not guaranteed by default on all devices even when hardware-capable — verify `Display.supportedModes`/`Surface.setFrameRate` is actually negotiating the high-refresh mode during gesture interaction, don't assume the system compositor picked it automatically.

---

## What to Build Toward

- Cross-platform parity checks: a lightweight internal tool/test that diffs the iOS and Android Smart Filter thresholds (blur variance cutoff, burst gap/similarity thresholds, large-video size cutoff) to catch silent drift between the two codebases' independently-implemented analysis algorithms.
- Predictive back gesture support (Android 14+ `OnBackAnimationCallback`/Compose Navigation's predictive back API) for the Review Bin full-screen viewer — the platform-native equivalent of a polished dismiss interaction, and a genuine Android-only capability worth building toward deliberately rather than porting from iOS.
- Foldable/large-screen adaptive layout for the card stack and Smart Filters grid (`WindowSizeClass`) — unlike the iOS app's deliberate Portrait-only lock (a considered iOS product decision, not a technical limitation), Android's device fragmentation makes at least basic large-screen layout adaptation a near-mandatory Play Store quality bar, not an optional future feature. Treat this as a real near-term requirement, not a "someday" item, even though the equivalent iOS section explicitly defers landscape/iPad work.
- Widget/App Widget surfacing "N items in Review Bin" or session savings — no direct iOS analogue requested yet, but a natural extension of the existing gamified savings-bar concept onto a platform-native surface Android offers and iOS (pre-widget-interactivity) does not as cleanly.
