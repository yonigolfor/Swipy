# Android — Known Issues / TODO

Running backlog of bugs and gaps found while dogfooding the app on a physical device
(Samsung Galaxy A36, Android 16). Each item should be resolved and checked off one at a time,
not batched — see root `CLAUDE.md`'s Documentation Hygiene rule: update this file in the same
commit as the fix.

---

## 1. Haptic feedback audit — 🟡 PARTIALLY RESOLVED (swipe commits only)

No haptic feedback existed anywhere in the Android app — confirmed via a full-repo grep, zero
hits for any vibration/haptic API usage outside of doc comments. iOS has a dedicated
`HapticService` with a distinct pattern per swipe direction (see root `CLAUDE.md` → "Haptics"
and `HAPTICS.md` for the full event map).

**Fix applied**: new `HapticManager` (`:core:designsystem/haptics/`, `@Singleton`, reached from
Compose via `rememberHapticManager()` — the same `EntryPointAccessors` bridge pattern as
`VideoPlayerPoolEntryPoint`/`rememberVideoPlayerPool()`). Uses `VibrationEffect.createOneShot`/
`createWaveform` (API 26+, safe at `minSdk = 29`) via `VibratorManager` on API 31+ / legacy
`Vibrator` below. Ported `HAPTICS.md`'s exact Swipe Actions intensities — `keep()` (light,
amplitude 255) and `snooze()` (light, amplitude 153) share the same short one-shot shape,
differing only by amplitude exactly like iOS's two `.light`-style generators differing only by
intensity scalar; `delete()` is a double-pulse waveform (heavier feel, plus the requested
double-pulse — iOS itself uses a single heavy tap, so the double-pulse is a deliberate Android
enhancement, not a literal port). Wired directly into `CardStackLayer.kt`: `thresholdCrossed()`
(amplitude 76) fires on every drag direction-lock transition, `keep()`/`delete()`/`snooze()`
fire at the exact swipe-commit moment in `onDragEnd`. `thresholdCrossed()` itself has no iOS
equivalent on the real card stack (confirmed against `HAPTICS.md` — iOS's only drag-time haptic,
`.soft`, is exclusive to the onboarding demo card) — an intentional Android-only addition.

**Still open**: Undo, Shuffle activate/land, and the Session Savings Bar milestone
celebration burst have no haptic wiring yet — out of scope for this pass, which focused on the
swipe-commit path `CardStackLayer.kt` owns directly.

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

## 7. Local Notifications Engine & Scheduling — 🟡 INFRASTRUCTURE BUILT, TRIGGERS PARTIALLY WIRED

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
2. **Photo burst trigger** — not checked by the Worker at all yet. Blocked on the same missing
   `MediaStore` `ContentObserver` noted in `android/CLAUDE.md`'s "MediaStore Querying" section —
   do not add a naive "count photos every worker run" check in the meantime; that reintroduces
   the exact baseline-drift bug class `NOTIFICATIONS.md` documents iOS having already fixed once
   (the baseline must only advance when a notification actually fires).
3. **Swipe-limit-reset trigger** — `NotificationScheduler.scheduleExact(SwipeLimitReset, ...)`
   is a complete, callable API, but nothing calls it yet — there's no Android port of iOS's
   `DailyLimitService`/swipe-cap state in `PhotoStackViewModel` for it to hook into. Wire it in
   once that daily-limit feature exists on Android.
4. **Review Bin reminder's 24h condition is a coarser proxy than iOS's real one** —
   `PhotoStateRepository.reviewBinIds` is a bare id list with no per-item "added at" timestamp,
   so the Worker currently fires whenever the bin is simply non-empty (debounced only by the
   notification id's replace-not-stack behavior and the daily quota), not "24h since first
   unresolved item" like iOS. Would need a new persisted timestamp field to close this gap
   properly.
5. **Per-trigger-type notification channels** — currently one shared `swipy_reminders` channel.
   Splitting by trigger type is a genuine Android capability with no iOS analogue (iOS has no
   per-category user-facing mute toggle the way Android's per-channel settings do) worth a
   deliberate decision rather than defaulting to iOS's single-category shape.
