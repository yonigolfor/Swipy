# Android — Known Issues / TODO

Running backlog of bugs and gaps found while dogfooding the app on a physical device
(Samsung Galaxy A36, Android 16). Each item should be resolved and checked off one at a time,
not batched — see root `CLAUDE.md`'s Documentation Hygiene rule: update this file in the same
commit as the fix.

---

## 1. Haptic feedback audit

No haptic feedback exists anywhere in the Android app today — confirmed via a full-repo grep,
zero hits for any vibration/haptic API usage outside of doc comments. iOS has a dedicated
`HapticService` with a distinct pattern per swipe direction (see root `CLAUDE.md` → "Haptics"
and `HAPTICS.md` for the full event map: Keep/Delete/Snooze each get their own
`UIImpactFeedbackGenerator` style, plus the Session Savings Bar's multi-beat celebration burst,
undo, shuffle land, etc.).

**To do:**
- Port `HapticService` as an Android equivalent — `android.os.VibrationEffect` /
  `HapticFeedbackConstants` (or `androidx.compose.ui.hapticfeedback.HapticFeedback` for
  Compose-native call sites) mapped to the same event set iOS uses.
- Wire it into every swipe commit (Keep/Delete/Snooze), Undo, Shuffle activate/land, and the
  Session Savings Bar milestone celebration — mirroring `HAPTICS.md`'s event map.

---

## 2. Hebrew / RTL localization

No localization system is wired up — confirmed via grep, only one incidental `stringResource`
call in the whole Android codebase (`SessionSavingsBar.kt`); every other string is a hardcoded
English literal. iOS uses `String(localized:)` everywhere against `Localizable.xcstrings` with
both `en` and `he` translations (see root `CLAUDE.md` → "Localization").

**To do:**
- Introduce `strings.xml` (+ `values-he/strings.xml`) and migrate every hardcoded string across
  all feature modules to `stringResource(R.string.*)`.
- Decide the Android equivalent of iOS's "pin layout direction to LTR app-wide" strategy (see
  item 3 below — the two issues are the same root cause) — i.e. whether Android should let
  `LocalLayoutDirection` follow the Hebrew system locale for **text/reading** layout (the
  Android-idiomatic default, and generally correct — RTL text flow is what Hebrew users expect)
  while still pinning **physical gesture directions** (swipe left/right, card drag) and
  **left/right-coded UI** (Keep/Delete badge sides) to be locale-independent, the same
  distinction iOS's own doc draws between "Hebrew text renders correctly regardless" and
  "container layout/gesture direction must not flip."

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

## 6. App icon is missing (using the default Android placeholder)

No launcher icon resources exist in `app/src/main/res` at all — confirmed via search, no
`mipmap-*/ic_launcher*` files present anywhere in the Android project. The app currently installs
with a generic/default icon.

**To do:**
- Source the icon from the iOS project (`Swipy/Assets.xcassets/AppIcon.appiconset` — blue
  gradient background, white "S" letter, per root `CLAUDE.md`'s "What This App Is" → App Icon
  line) and export/re-render it at the Android launcher icon sizes.
- Generate a proper adaptive icon (`mipmap-anydpi-v26/ic_launcher.xml` foreground/background
  layers) via Android Studio's Image Asset tool or `xmllint`-free manual export, not just a
  flat single-density PNG.
- Wire it into `AndroidManifest.xml`'s `<application>` tag — confirmed there's currently no
  `android:icon`/`android:roundIcon` attribute at all (not even a reference to a missing
  placeholder), and `app/src/main/res` has no `mipmap-*` directories whatsoever, only `values/`.
