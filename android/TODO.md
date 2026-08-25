# Android — Known Issues / TODO

Running backlog of bugs and gaps found while dogfooding the app on a physical device
(Samsung Galaxy A36, Android 16). Each item should be resolved and checked off one at a time,
not batched — see root `CLAUDE.md`'s Documentation Hygiene rule: update this file in the same
commit as the fix.

---

## 1. Haptic feedback audit — ✅ RESOLVED (full `HAPTICS.md` event map ported)

No haptic feedback existed anywhere in the Android app — confirmed via a full-repo grep, zero
hits for any vibration/haptic API usage outside of doc comments. iOS has a dedicated
`HapticService` with a distinct pattern per swipe direction (see root `CLAUDE.md` → "Haptics"
and `HAPTICS.md` for the full event map).

**Critical bug found and fixed during on-device dogfooding**: the very first physical-device
test after the initial haptics pass crashed on every real swipe with
`SecurityException: vibrate: Neither user ... nor current process has android.permission.VIBRATE`.
The `VIBRATE` permission was never added to `AndroidManifest.xml` — `vibrator.hasVibrator()`
only checks hardware capability, not this permission, so nothing in the build/compile/test
pipeline could have caught it; it only surfaces at the moment `Vibrator.vibrate()` actually
runs. Fixed by adding `<uses-permission android:name="android.permission.VIBRATE" />` (a normal,
not runtime-dangerous, permission).

**Fix applied**: `HapticManager` (`:core:designsystem/haptics/`, `@Singleton`, reached from
Compose via `rememberHapticManager()` — the same `EntryPointAccessors` bridge pattern as
`VideoPlayerPoolEntryPoint`/`rememberVideoPlayerPool()`). Uses `VibrationEffect.createOneShot`/
`createWaveform` (API 26+, safe at `minSdk = 29`) via `VibratorManager` on API 31+ / legacy
`Vibrator` below. Now covers every event in `HAPTICS.md`:

- **Swipe Actions**: `keep()`/`snooze()` (light, amplitude 255/153 — same shape, differ only by
  amplitude, exactly like iOS's two `.light` generators differing only by intensity scalar);
  `delete()` is a double-pulse waveform (iOS itself uses a single heavy tap — the double-pulse
  is a deliberate Android enhancement). Wired into `CardStackLayer.kt`'s `onDragEnd`.
  `thresholdCrossed()` (drag direction-lock crossing) has no iOS equivalent on the real card
  stack — an intentional Android-only addition.
- **Onboarding CTAs/demo cards**: `mediumTap()` wired once into the shared `GoldCapsuleButton`
  component (every onboarding CTA gets it for free, matching iOS's single-generator-for-every-
  CTA architecture) — not the literal per-button call sites iOS's own source has. `softTick()`
  wired into both demo cards' (`SwipeDemoStep`/`SnoozeIntroStep`) direction-change transitions,
  deliberately throttled to fire only on transitions rather than iOS's literal per-frame
  `softHaptic.impactOccurred()` call — `Vibrator.vibrate()` has no equivalent to UIKit's taptic-
  engine coalescing, so an unthrottled port would be a genuinely worse feel, not a faithful one.
- **UI Actions**: `selectionTick()` on Filter category tap (`FilterCategoriesScreen`'s
  `CategoryRow`); `shuffleActivate()` on the Shuffle FAB tap and `shuffleLand()` (two-beat) on
  `PhotoStackEffect.ShuffleLanded` (both in `SwipeStackScreen.kt`); `success()` on Undo — the
  Android-native trigger point standing in for iOS's shake gesture, which has no Android
  equivalent built.
- **GB Milestone crescendo**: `milestoneBurst()` — a single `VibrationEffect.createWaveform`
  atomically expressing the whole 6-beat pattern, wired into `SessionSavingsBar.kt`'s existing
  `celebrationTrigger` step (same ~360ms-after-fill timing `HAPTICS.md` specifies). Deliberately
  **not** a literal port of iOS's manual `DispatchQueue.asyncAfter`-sequenced generator calls —
  iOS needs that because a single `UIImpactFeedbackGenerator` call can't express a multi-beat
  pattern (the exact reason `HAPTICS.md` calls out `SessionSavingsBarView` as the one view
  allowed to bypass `HapticService`); `createWaveform` has no such limitation, so one atomic
  Android call is the more idiomatic primitive for this shape, not a workaround-for-a-workaround.
- **Empty Trash**: `emptyTrashBurst()` (triple-heavy, full intensity) wired into
  `ReviewBinScreen.kt`'s `ReviewBinEffect.EmptyTrashCompleted` handling.
- **Permission denied**: `error()` wired into `PermissionStep.kt` via
  `LaunchedEffect(isPermissionDenied)`, firing once per transition into denied (not on every
  recomposition while already denied), matching `HAPTICS.md`'s exact firing rule.

**Deliberately not wired — needs a UI feature that doesn't exist yet, not a haptics gap**:
Review Bin item restore's "poof" haptic (`HAPTICS.md`: soft impact/0.7, synced to iOS's
`.popping` → `.poofing` animation phase transition) — Android's restore is a plain instant
action with no distinct pop/poof animation phase to sync a haptic to yet. Revisit once/if that
animation is built; wiring a haptic to a nonexistent animation phase would be fake, not a real
port.

---

## 2. Hebrew / RTL localization — ✅ RESOLVED

No localization system was wired up — confirmed via grep, only one incidental `stringResource`
call in the whole Android codebase; every other string was a hardcoded English literal.

**Fix applied**: every module (`:app`, `:core:designsystem`, `:feature:swipe`,
`:feature:filters`, `:feature:reviewbin`, `:feature:onboarding`) now has its own
`res/values/strings.xml` + `res/values-he/strings.xml`, with every user-facing string migrated
to `stringResource(R.string.*)` (or `pluralStringResource` for the Review Bin's item-count
sentences, which needed real quantity handling — Hebrew's plural rules differ from English's).
Brand-name text ("Swipy", the app icon's "S" letter) is deliberately left untranslated, matching
`app_name`'s own convention. Unit abbreviations ("MB"/"GB") are also left untranslated,
matching standard SI-unit convention.

Three strings (`swipe.keep`/`swipe.delete`/`swipe.later`) are shared between the real swipe
stack (`SwipeIndicator.kt`) and the onboarding demo cards (`SwipeDemoStep.kt`/
`SnoozeIntroStep.kt`) — both already depend on `:core:designsystem`, and iOS's own
`Localizable.xcstrings` uses the identical keys for both, so they live there once instead of
duplicating (and risking translation drift) per module. `SwipeDemoStep.kt`'s `DemoCard` needed a
real refactor beyond a string swap: it used to compare the *rendered label text* against a
hardcoded `"Delete"` literal to pick the badge color/rotation — correct only in English. Replaced
with a `DemoSwipeDirection` enum stored in state, with text/color both derived from the enum at
render time.

Item 3's RTL fix (`AbsoluteAlignment` for the real swipe badges) already matches
`android/CLAUDE.md`'s prescribed approach: Android lets `LocalLayoutDirection` follow the Hebrew
system locale for **text/reading** layout (confirmed via audit — `CardStackLayer.kt`'s drag math
is pure pointer-offset with no `Start`/`End` usage anywhere, and `PhotoCardComposable.kt`'s info
badges correctly use `TopStart`/`TopEnd`, since those are general UI chrome that *should* mirror
under RTL, not gesture-direction-tied), while physical gesture-direction UI
(`SwipeIndicator.kt`'s Keep/Delete badges) stays locale-independent. No app-wide LTR pin needed,
unlike iOS.

**Not yet tested on an actual Hebrew-locale device** — no such device was available this pass;
worth a real on-device RTL pass before considering this pixel-final.

---

## 3. Swipe badge appears on the wrong side — ✅ RESOLVED

Swiping the card physically **right** used to show the "Keep" badge on the **left** edge of
the screen instead of the right.

**Root cause**: `SwipeIndicator.kt:39-40` used `Alignment.CenterStart` (Delete) /
`Alignment.CenterEnd` (Keep) — both are **layout-direction-aware** in Compose. Under an RTL
`LocalLayoutDirection` (which Compose adopts automatically from a Hebrew system locale unless
explicitly overridden), `CenterStart` resolves to the physical **right** edge and `CenterEnd`
resolves to the physical **left** edge — exactly inverted from LTR. This is the direct Android
analogue of the bug iOS's root `CLAUDE.md` documents at length under "Layout Direction — Pinned
to LTR App-Wide".

**Fix applied**: swapped `Alignment.CenterStart`/`CenterEnd` for `AbsoluteAlignment.CenterLeft`/
`CenterRight` in `SwipeIndicator.kt` — both implement `Alignment` but are never layout-direction
-aware, matching android/CLAUDE.md's prescribed approach (Android should let text/reading layout
follow RTL, but physical gesture-direction UI must stay locale-independent) rather than
adopting iOS's app-wide LTR pin.

**Still open, deferred to item 2's RTL work**: audit `CardStackLayer.kt`'s drag-direction
resolution and fling targets for the same class of bug — the drag math is already raw
pointer-offset based (direction-agnostic), so it's likely fine, but not yet confirmed
end-to-end on an actual Hebrew-locale device (no such device available this pass).

---

## 4. Main tab should default to Swipe, not Filters — ✅ RESOLVED

`MainActivity.kt`'s `SwipyNavHost` had `startDestination = ROUTE_FILTERS` — the app opened on
the Smart Filters/Categories screen. iOS defaults to the Swipe tab (`ContentView.swift`:
`@State private var selectedTab = 1`) — Filters is reachable but not the landing screen.

**Fix applied**: `startDestination` changed to `ROUTE_SWIPE`.

**Unplanned but necessary companion fix**: `PhotoStackViewModel` never auto-loads on `init` —
it stays empty until `PhotoStackIntent.LoadPhotos(filter)` is sent, which previously only
happened when the user tapped a category on the Filters screen. Landing directly on Swipe would
otherwise show a permanently empty stack with no way to populate it. `SwipyNavHost` now fires
`LoadPhotos(FilterCategory.All)` once via a `LaunchedEffect(Unit)` guarded on the stack actually
being empty, so it never re-fires redundantly after a real load has run.

---

## 5. Smart Filters counts are inconsistent / don't make sense together — ✅ RESOLVED

Observed on-device: **All Photos: 100**, while individual sub-category counts (e.g. Screenshots:
99+, Videos: 13, plus several more categories) clearly summed to well more than 100 in the real
library.

**Root cause**: Phase 1 fast counts are capped at 100 for *every* category, `.All` included
(`FilterCategoriesViewModel`'s `CAP = 100`, `GetCategoryCountUseCase`). iOS special-cases `.all`
to show a real, uncapped total instead of the shared "99+" ceiling — a bare capped number like
"100" for the whole-library category reads as a precise small count, not an estimate.

**Fix applied**: new `GetTotalCategoryCountUseCase` (`:domain`) wraps the existing, previously
Shuffle-only `PhotoRepository.totalCount(filter)`. `FilterCategoriesViewModel.refresh()` now
overrides the Phase-1 capped entry for `FilterCategory.All` with
`(totalCount(All) - excludedIds.size).coerceAtLeast(0)` — every other category keeps the
capped/`"99+"` Phase-1 behavior unchanged. The subtraction is exact, not approximate:
`FilterCategory.All`'s MediaStore selection matches every image/video row with no further
predicate (confirmed in `MediaStoreQueryBuilder`), so every already-swiped id (kept/binned/
snoozed) is guaranteed a member of that raw total.

---

## 6. App icon is missing — ✅ RESOLVED

No launcher icon resources existed in `app/src/main/res` at all — no `mipmap-*/ic_launcher*`
files anywhere in the Android project, no `android:icon`/`android:roundIcon` in the manifest.
The actual iOS icon (`Swipy/Assets.xcassets/AppIcon.appiconset/AppIcon.png`, 1024×1024) turned
out to be a stylized cyan "S"-shaped double-arrow glyph on a navy gradient — not literally
"blue background, white S letter" as this doc's own earlier description assumed; used the real
asset as source of truth per the explicit instruction to pull it from the iOS app.

**Fix applied**: an adaptive icon (`mipmap-anydpi-v26/ic_launcher.xml` +
`ic_launcher_round.xml`), not a flat single-density PNG:
- `drawable/ic_launcher_background.xml` — a linear gradient sampled from the source PNG's own
  corner pixels (`#041235` bottom → `#12305F` top), so it visually continues the source art's
  own background rather than a flat guess.
- `drawable/ic_launcher_foreground_art.png` — the source PNG downscaled to 432×432 (Google's
  recommended raw-asset resolution for a 108dp/4x adaptive-icon layer) via Pillow.
- `drawable/ic_launcher_foreground.xml` — wraps the art in a 19%-inset `<inset>` drawable so it
  sits within the adaptive icon's ~66dp safe-zone circle and is never clipped by a circular/
  squircle launcher mask. The source PNG has no alpha channel (flat RGB, glyph+background baked
  together as one square) — rather than attempting to isolate the glyph via pixel-thresholding
  (fragile, real risk of a rough/amateurish edge on a "sleek" launcher icon), the *entire* flat
  square is used as the foreground layer, insetted; since its own baked-in background closely
  matches the separate background layer's gradient, the seam at the mask edge is effectively
  invisible.
- No legacy per-density raster `mipmap-*/ic_launcher.png` fallback — `minSdk = 29` guarantees
  API 26+ on every supported device, so `mipmap-anydpi-v26`'s adaptive-icon XML is always what
  resolves; a raster fallback would be genuinely unreachable dead weight (same "don't keep a
  legacy path alive below minSdk" reasoning `android/CLAUDE.md`'s Code Quality Standard already
  applies to the pre-API-30 delete-request branch).
- `AndroidManifest.xml`'s `<application>` tag now sets `android:icon="@mipmap/ic_launcher"` and
  `android:roundIcon="@mipmap/ic_launcher_round"`.

---

## 7. Local Notifications Engine & Scheduling — 🟡 6/6 TRIGGERS WIRED, NOT YET VERIFIED ON-DEVICE

iOS has a fully built-out system (`NOTIFICATIONS.md`,
`Services/NotificationManager.swift`/`NotificationScheduler.swift`/`NotificationDelegate.swift`)
with **6 trigger types** and a **2-notification/day quota**:

1. **Review Bin reminder** — 24h after items sit in the bin unresolved; refreshed with live
   bin-size data on every foreground (same notification id, no duplicate).
2. **Photo burst** — 50+ new photos since the last-checked baseline. Two independent paths:
   foreground (real-time via a library change observer) and background (periodic check,
   `iOS: BGAppRefreshTask`, not guaranteed-timing). iOS learned two real bugs here worth not
   re-discovering: (a) the baseline must only advance when a notification actually fires, or a
   diff that's still under 50 silently resets and never accumulates across background runs; (b)
   the very first baseline read must gate on library permission being granted, or a cold-start
   race (initial baseline captured before onboarding even requests access) reads `0` and causes
   a false "3000-photo burst" notification the moment access is later granted.
3. **Milestone** — fires once per whole GB crossed in `totalSpaceSavedLifetime` (persisted
   high-water-mark, not per-swipe).
4. **Swipe limit reset** — scheduled for 00:01 the next day, the instant a free user hits their
   daily swipe cap; exact one-shot delivery, not repeating; cancelled early if the day rolls
   over before firing (user reopens before midnight). Does **not** count against the 2/day quota
   (self-initiated, functional, not an engagement nudge).
5. **Weekly cleanup** — every Sunday 21:30, OS-guaranteed recurring delivery (`repeats: true`
   equivalent) so a user who never reopens the app still gets it forever; content is a random
   pick from a small copy-variant pool, re-rolled (not re-guaranteed — the recurrence itself
   doesn't depend on this) on every foreground for users who do return often. Also excluded from
   the 2/day quota.
6. **Inactivity reminder** — 72h since last foreground, rescheduled (cancel + re-arm) on every
   foreground so the countdown always restarts from the most recent open. Excluded from the
   2/day quota (persistent reminder, not event-driven).

Deep linking: tapping any notification opens the app to a specific tab (`filters`/`swipe`/
`reviewBin`), delivered via a notification-center post the root view listens for.

**Infrastructure built** — new `:core:notifications` module (Hilt-enabled Android library),
wired into `:app`:
- `NotificationTrigger` — the 6 triggers as an enum, each with a stable notification id (doubles
  as `PendingIntent` request code, so re-posting the same trigger replaces rather than stacks)
  and a `deepLinkRoute` matching `MainActivity`'s route constants.
- `SwipyNotificationManager` — creates the `swipy_reminders` channel and posts/cancels
  notifications, with a deep-link `PendingIntent` built via `packageManager.getLaunchIntentForPackage`
  (this module can't reference `:app`'s `MainActivity` class directly — wrong dependency
  direction — so the launcher Activity is targeted generically instead).
- `NotificationScheduler` — `AlarmManager.setExactAndAllowWhileIdle` for the 3 exact triggers,
  per the plan below.
- `AlarmReceiver`/`BootReceiver` (`@AndroidEntryPoint` `BroadcastReceiver`s, declared in this
  module's own merged manifest) — `AlarmReceiver` posts the notification and self-reschedules
  the weekly trigger for next Sunday (`AlarmManager` has no `repeats: true` for exact alarms);
  `BootReceiver` re-arms the weekly/inactivity alarms after a reboot, since exact alarms don't
  survive one.
- `SwipyNotificationWorker` (`@HiltWorker`, registered via `SwipyApplication`'s
  `Configuration.Provider` + `HiltWorkerFactory` — required the default WorkManager
  `androidx.startup` initializer to be explicitly removed in `:app`'s manifest, or app startup
  crashes with "WorkManager is already initialized") — a `PeriodicWorkRequest` (6h, matching
  iOS's own requested cadence) checking Review Bin reminder + Milestone. **Both checks are real,
  not stubs** — they read `PhotoStateRepository.reviewBinIds`/`totalSpaceSavedLifetime`
  (already existed) directly.
- `NotificationStateStore` — reuses the app's single shared `DataStore<Preferences>` instance
  (injected by type only, no `project(":data:datastore")` dependency needed — Hilt resolves it
  via the app-level aggregated graph) rather than opening a second competing DataStore file.
  Tracks `lastMilestoneNotifiedGb` and implements the real 2/day quota
  (`tryConsumeDailyQuota()`, gates Review Bin/Milestone/Burst only, matching `NOTIFICATIONS.md`
  exactly — the 3 exact-alarm triggers are correctly never gated by it).
- `MainActivity` reads the deep-link route extra in both `onCreate` and `onNewIntent` (tapping a
  notification while the app is already running redelivers via `onNewIntent`, since this is a
  single-Activity app) and threads it down to `SwipyNavHost`. **Real bug caught while wiring
  this**: `NavHost`'s `startDestination` param rebuilds (and resets) the whole nav graph if its
  value changes across recompositions — naively passing the live deep-link parameter straight
  through would have wiped the back stack the instant the deep link was marked consumed
  (flipping back to null). Fixed by capturing the initial route once via a keyless `remember`,
  decoupled from the live parameter that only drives an explicit `navigateToTab()` call for the
  warm-start case.
- Manifest: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM` (not `USE_EXACT_ALARM` — that's a
  Play-Store-restricted permission reserved for alarm-clock/calendar-class apps), and
  `RECEIVE_BOOT_COMPLETED` all added to `:app`'s `AndroidManifest.xml`.
- Localization: `:core:notifications` has its own `res/values/strings.xml` +
  `res/values-he/strings.xml` for all 6 triggers' title/body (the weekly-cleanup 2-variant pool
  reuses real, already-shipped iOS Hebrew copy from `NOTIFICATIONS.md` where available, adapted
  from "your iPhone" to "your phone" for the Android context) plus a `<plurals>` for the Review
  Bin item count.

**Still open / explicitly not wired this pass:**
1. ~~Runtime permission request UI~~ — ✅ RESOLVED. `SwipyNavHost`'s first composition now
   calls `rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission())` for
   `POST_NOTIFICATIONS` on API 33+, gated on `ContextCompat.checkSelfPermission` so it never
   fires if already granted. Fires once per cold start (the same granularity as iOS's
   `ContentView.onAppear`, since `SwipyNavHost` is entered once per app process lifetime in
   practice) — timed to match iOS's own HIG-driven choice to prompt **after** onboarding, not
   during. No manual "already asked" tracking needed: the OS itself silently stops showing the
   dialog after two denials (or "Don't ask again"), so this can't become a re-prompt loop. No
   dedicated in-app recovery/Settings-redirect UI on denial — notifications are a background
   enhancement here, not a blocking gate like gallery access, matching iOS's own fire-and-forget
   `requestAuthorization` call (no visible in-app fallback documented for it either).
2. ~~Photo burst trigger~~ — ✅ RESOLVED, two independent paths mirroring `NOTIFICATIONS.md`
   exactly. **New `:domain` interface `MediaChangeNotifier`** (`observeChanges(): Flow<Unit>`),
   implemented in `:data:mediastore` as `MediaStoreChangeNotifier` — a `callbackFlow` wrapping a
   `ContentObserver` on `MediaStore.Files.getContentUri(VOLUME_EXTERNAL)` (the same collection
   `MediaStorePhotoRepository` itself queries, so no separate Images/Video registration needed).
   Kept in `:domain` rather than requiring `:core:notifications` to depend on `:data:mediastore`
   directly — resolved via Hilt's app-level graph, same pattern as `NotificationStateStore`'s
   `DataStore<Preferences>` injection. **Foreground path**: new `PhotoBurstMonitor` (`@Singleton`)
   debounces (`3s`) the observer's events, compares `PhotoRepository.totalCount(All)` against an
   in-memory `burstSessionBaseCount` — the direct analogue of iOS's `burstSessionBaseCount`,
   reset every foreground via `resetSessionBaseline()`. **Background path**:
   `SwipyNotificationWorker.checkPhotoBurstTrigger()` compares the same total count against a
   *persisted* `NotificationStateStore.lastKnownPhotoCount` baseline — ported iOS's two documented
   bug fixes exactly: the baseline only advances when a notification actually fires (a diff still
   under 50 leaves it untouched so it accumulates across runs), and the very first baseline is
   only captured once media permission is confirmed granted (`ContextCompat.checkSelfPermission`),
   never seeded as a false `0` before onboarding requests access. Both paths share
   `NotificationStateStore.lastBurstNotifiedAt` (24h re-fire cooldown) and the existing daily quota.
3. ~~Swipe-limit-reset trigger~~ — ✅ RESOLVED, now that item 9's `SwipeQuotaRepository` exists.
   `PhotoStackViewModel.scheduleSwipeLimitResetIfNeeded()` calls
   `NotificationScheduler.scheduleExact(SwipeLimitReset, nextMidnightPlusOneMinuteMillis())`
   (new public helper, `core/notifications/NotificationTiming.kt`) the moment a Keep/Delete swipe
   exhausts the daily quota for a non-premium, entitlement-resolved user — same three-way guard
   as iOS's `scheduleSwipeLimitResetIfNeeded()`. `NotificationForegroundCoordinator.onStart` also
   opportunistically cancels a stale alarm once the quota is no longer exhausted (mirrors iOS's
   own `resetIfNewDay()` cancellation — also not a dedicated day-boundary watcher on iOS either).
4. ~~Review Bin reminder's 24h condition is a coarser proxy than iOS's real one~~ — ✅ RESOLVED.
   `PhotoStateRepository` gained `reviewBinAddedAt: Flow<Map<Long, Long>>` (epoch millis, set only
   on an id's *first* addition — an undo/re-swipe of an already-binned id doesn't reset its
   clock), persisted the same JSON-blob way as the existing `reviewBinFileSizes` map.
   `checkReviewBinReminder()` now gates on `now - oldestUnresolvedTimestamp >= 24h`, matching iOS
   exactly instead of firing on "bin merely non-empty."
5. **Persistent reminders now re-arm on every foreground, matching iOS** — ✅ RESOLVED
   (found while porting the above, not originally listed as a gap, but a real behavioral drift
   from iOS: `armPersistentReminders()` previously only ran once in `SwipyApplication.onCreate()`,
   so a user who reopened the app multiple times within one process never got their 72h
   inactivity countdown reset, unlike iOS's `scenePhase == .active` handler which does this every
   time). New `NotificationForegroundCoordinator` (`@Singleton`) registers a
   `ProcessLifecycleOwner` observer (the app-wide, not per-`Activity`, foreground signal — the
   correct native analogue of `scenePhase`) that on `ON_START` calls both
   `photoBurstMonitor.resetSessionBaseline()` and `scheduler.armPersistentReminders()` (already
   idempotent/replace-based, safe to call repeatedly). `SwipyApplication.onCreate()` no longer
   arms anything directly — mirrors iOS's own choice to defer this to first `scenePhase == .active`
   rather than `didFinishLaunching`; `BootReceiver` still covers the reboot-with-no-UI-opened case.
6. **Per-trigger-type notification channels** — currently one shared `swipy_reminders` channel.
   Splitting by trigger type is a genuine Android capability with no iOS analogue (iOS has no
   per-category user-facing mute toggle the way Android's per-channel settings do) worth a
   deliberate decision rather than defaulting to iOS's single-category shape. Not part of this
   pass — single-channel already matches iOS parity; revisit as an Android-only enhancement.

**Not yet tested on a physical device** — same caveat as items 2 and 10: a `ContentObserver`
firing on a genuine bulk photo import, and the 24h Review Bin/burst-cooldown timers, cannot be
exercised live without a physical device and real elapsed time. `./gradlew :app:assembleDebug
test` passes; this pass verifies the new logic by compilation and code review, not a live run.

---

## 8. Paywall Integration & Play Billing — 🟡 IMPLEMENTED, NOT YET VERIFIED WITH REAL PURCHASES

Full port of iOS `PaywallView.swift` + `PremiumManager.swift`, including both presentation
contexts. `:feature:paywall` (`PaywallContext`, `PaywallUiState`, `PaywallIntent`,
`PaywallViewModel`, `PaywallScreen` + strings in `values`/`values-he`) and a new `:data:billing`
module (`BillingManager`, Play Billing Library 7.1.1 via `libs.android.billing.ktx`).

**Module design** — `PremiumRepository` (`:domain`) is deliberately state-only
(`isPremium`/`hasActiveSubscription`/`hasResolvedEntitlements`), not the full iOS
`PremiumManager` surface: `BillingClient.launchBillingFlow` requires an `Activity`, which
`:domain` can never reference. Products/purchase/restore/isPurchasing/errorMessage all live on
`BillingManager` (`:data:billing`) directly — `:feature:paywall` injects it concretely, the same
pattern `:feature:swipe` already uses for `:data:mediastore`'s `VideoPlayerPool`
(`VideoPlayerPoolAccess.kt`). `:feature:swipe`'s swipe-block gate (item 9) only ever needs the
three state flows, so it depends on `:domain`'s `PremiumRepository` alone — zero dependency on
`:feature:paywall` or `:data:billing`.

**Play Console product model (a real platform difference from iOS, not an oversight)**: iOS uses
two flat subscription product ids (`monthlySubscription`/`yearlySubscription`) in one
subscription group so StoreKit treats switching between them as upgrade/downgrade. Play Billing's
equivalent is **one subscription product with two base plans** (`monthly`/`yearly`) — Google's
recommended shape for the same upgrade/downgrade behavior — plus one separate one-time product
for Lifetime. `BillingManager` assumes product ids `swipy_premium_subscription` (base plans
`monthly`/`yearly`) and `swipy_lifetime_purchase` — **these must be created in Play Console
before any real purchase/restore flow can be tested**; nothing in this pass can verify that
independently of Play Console configuration existing.

Entitlement-resolution race ported exactly: `BillingManager.isPremium` seeds from a cached
DataStore boolean (`cached_is_premium`) at construction — the closest achievable Android analogue
of iOS's literal synchronous `PersistenceService.cachedIsPremium` seed (DataStore has no
synchronous read API, so this resolves on the next coroutine dispatch rather than truly frame-0,
but in practice completes well before first composition). `hasResolvedEntitlements` only flips
true once `queryPurchasesAsync` completes, run concurrently with `queryProductDetails` (not
sequentially) — the same fix iOS's `PremiumManager` doc already documents needing.

**Verified**: `:domain`/`:data:billing`/`:feature:paywall` all compile cleanly,
`./gradlew :app:assembleDebug test` passes. **Not verified**: an actual Play Billing purchase,
restore, or subscription upgrade/downgrade flow — that needs the Play Console products above
plus a license-tester account, neither of which exist yet.

**Code-review pass (post-implementation)** hardened `BillingManager`'s error handling: checks
`launchBillingFlow`'s return value (was leaving `isPurchasing` stuck `true` on a synchronous
failure), silences `USER_CANCELED` instead of surfacing it as an error (matches iOS's
`case .userCancelled: break`), checks `BillingResult.responseCode` on both product/purchase
queries instead of treating a network drop as "no products," and adds a `ProcessLifecycleOwner`
observer that re-verifies entitlements on every foreground (Play Billing has no equivalent of
iOS's always-live `Transaction.updates` for a purchase resolving outside the current session). See
`android/CLAUDE.md` "Paywall & Swipe Quota" for the full design this now reflects.

---

## 9. Swipe Quota (DailyLimitService) — 🟡 IMPLEMENTED, NOT YET VERIFIED ON-DEVICE

Full port of iOS `DailyLimitService`. New `:domain` interface `SwipeQuotaRepository`
(`dailyLimit`/`swipesUsedToday`/`bonusSwipesGranted`/`remainingSwipes`/`hasReachedLimit`/
`hasSharedToday` as eagerly-collected `StateFlow`s, plus `canSwipe`/`recordSwipe`/
`applyShareBonus`), implemented by `:data:datastore`'s `DataStoreSwipeQuotaRepository` — same
`dataStore.edit{}` atomicity pattern as `DataStorePhotoStateRepository`, persisted as 4 flat keys
in the existing shared `swipy_prefs` DataStore (`swipe_quota_used_today`,
`swipe_quota_date_epoch_day`, `swipe_quota_bonus`, `swipe_quota_bonus_date_epoch_day` — epoch-day
integers, the DataStore-friendly analogue of iOS's `Calendar.startOfDay` comparison). 120/day +
one-time +50 share bonus, identical constants to iOS.

**Why `StateFlow`, not a suspend/cold read**: iOS's gate check
(`shouldBlockSwipeForPaywall`) is synchronous, evaluated inline inside a perf-critical
gesture-end handler. `DataStoreSwipeQuotaRepository` eagerly collects (`SharingStarted.Eagerly`)
into `StateFlow`s so `canSwipe(isPremium: Boolean): Boolean` can read `.value` with zero
suspension — the direct Android analogue of iOS's `@Published` properties being readable without
an `await`.

`PhotoStackViewModel.handleSwipe` ports `CardStackView.dragGesture.onEnded`'s
`shouldBlockSwipeForPaywall` gate exactly (only Keep/Delete count against quota, never
Snooze/Undo; blocked only once `PremiumRepository.hasResolvedEntitlements` is true, matching
iOS's fresh-install cold-start race guard) and fires `PhotoStackEffect.ShowPaywall` — the exact
"navigate to paywall" example android/CLAUDE.md's Architecture section already names as the
canonical thing that must be an Effect, never boolean state. `SwipeStackScreen` takes a new
`onShowPaywall` param (same shape as `ReviewBinScreen`'s `onBack`) so `:feature:swipe` never
depends on `:feature:paywall`; `MainActivity` wires it to a `navController.navigate("paywall")`
push. The `.postOnboarding` presentation context is handled by `MainActivity.AppRoot` itself (a
local one-shot `showPostOnboardingPaywall` flag flipped by `OnboardingScreen`'s existing
`onComplete` callback) rather than embedding `PaywallScreen` inside `:feature:onboarding` — same
end-to-end sequence as iOS (onboarding → paywall → main app) without a new feature-to-feature
module dependency.

**Documented platform deviation**: the in-paywall "Share & Get Free Swipes" bonus is granted the
moment Android's `Intent.createChooser` share sheet returns control to the app — unlike iOS's
`UIActivityViewController` completion handler, `ACTION_SEND` gives no reliable signal that the
user actually completed (vs. cancelled) the share. This is a real Android platform limitation,
not an oversight (see `PaywallIntent.ShareCompleted`'s doc comment).

**Verified**: compiles cleanly, `./gradlew :app:assembleDebug test` passes. **Not verified**: the
120-swipe cap, day-rollover reset, and share bonus have not been exercised live on a device or
over real elapsed time — same class of caveat as items 2/7's notification timers.

**Code-review pass (post-implementation)** found a real bug in the gesture layer, not this
repository: `CardStackLayer.endDrag()` was flinging a Keep/Delete off-screen unconditionally,
with no awareness that `handleSwipe` was about to silently block it — the card ended up stranded
off-screen once the Paywall was dismissed, since the stack itself was never mutated. Fixed by
extracting the gate into a public `PhotoStackViewModel.canCommitSwipe(action)` and having
`CardStackLayer` check it *before* choosing fling-vs-snap-back, mirroring iOS's own
`dragGesture.onEnded` ordering (block check before the exit animation, not after). Full writeup
in `android/CLAUDE.md`'s new "Gesture-Layer Veto" subsection under Gesture Engine.

---

## 10. Pinch-to-Zoom on Top Card — 🟡 IMPLEMENTED, NOT YET VERIFIED ON-DEVICE

Ported from iOS's `CardStackView.swift` "Pinch Gesture" section + `SwipeStackView.swift`'s
dim-overlay/`isPinching` wiring.

**Fix applied**: `CardStackLayer.kt`'s single `detectDragGestures` call was replaced with a
custom `awaitEachGesture` loop that arbitrates 1-finger swipe vs. 2+-finger pinch by inspecting
the live pointer count each event — Compose has no SwiftUI-style "simultaneousGesture
auto-routes by finger count" primitive, so this is hand-rolled from the same public building
blocks `detectTransformGestures` itself uses (`PointerEvent.calculateZoom()`/`calculatePan()`/
`calculateCentroid()`). Entering a pinch resets any in-flight drag offset/rotation to zero
(mirrors iOS's identical reset in `pinchGesture.onChanged`); a pinch ending while one finger
remains down does not retroactively start a swipe (mirrors SwiftUI gesture-recognizer
exclusivity) via a `pinchEndedThisGesture` flag. Touch-slop is hand-implemented
(`viewConfiguration.touchSlop`) since the custom detector fully replaces `detectDragGestures`,
which used to provide it internally.

Card transform is split across **two** stacked `graphicsLayer` modifiers, not one — a single
`graphicsLayer` shares one `transformOrigin` between `scaleX/Y` and `rotationZ`, but iOS's
`.scaleEffect(pinchScale, anchor:)`/`.rotationEffect()` are independent modifiers with
independent anchors (rotation always about center regardless of the pinch anchor). Stacking two
layers (scale+translate anchored at `pinchAnchor`, then a separate layer for `rotationZ` at the
default center origin) is what lets Compose reproduce that independence — necessary because
`pinchAnchor` is deliberately never reset after a pinch ends (matches iOS, avoids a jump on the
next zoom), so a subsequent normal swipe's rotation would otherwise pivot around a stale
off-center point instead of the card's own center. Release springs `pinchScale → 1f` /
`pinchOffset → Offset.zero` via the same `animate()`-into-`mutableFloatStateOf` pattern used for
the drag release animation (see item 3 of the architecture audit fixes) — not raw `Animatable`,
consistent with this file's per-frame-state discipline. `SwipeStackScreen.kt` hoists a discrete
`isPinching` boolean (via `onPinchStateChanged`, never the per-frame pinch values themselves) to
elevate the card layer's `zIndex` to 200 and fade in a `0.55`-alpha black scrim (`tween(200)` in,
instant snap out) — matches iOS's `zIndex(isPinching ? 200 : 0)` / dim-overlay spec exactly.

**Deliberately not ported**: iOS also hides the tab bar during a pinch. Android's bottom
`NavigationBar` has no hide-on-gesture wiring at all yet (confirmed via grep — not even for the
existing drag), so nothing to hook into here; revisit once nav-hide exists for any reason.

**Not yet tested on a physical device** — no device was connected this pass (`adb devices`
returned empty). `./gradlew :app:assembleDebug test` passes, but pinch-to-zoom is multi-touch,
`graphicsLayer`-composition-order-sensitive gesture code — verify the actual zoom/pan feel,
touch-slop threshold, and anchor-point accuracy on-device before considering this pixel-final,
same caveat as item 2's RTL work.
