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

## 3. Swipe badge appears on the wrong side (root cause identified, not yet fixed)

Swiping the card physically **right** shows the "Keep" badge on the **left** edge of the
screen instead of the right.

**Root cause**: `SwipeIndicator.kt:39-40` uses `Alignment.CenterStart` (Delete) /
`Alignment.CenterEnd` (Keep) — both are **layout-direction-aware** in Compose. Under an RTL
`LocalLayoutDirection` (which Compose adopts automatically from a Hebrew system locale unless
explicitly overridden), `CenterStart` resolves to the physical **right** edge and `CenterEnd`
resolves to the physical **left** edge — exactly inverted from LTR. This is the direct Android
analogue of the bug iOS's root `CLAUDE.md` documents at length under "Layout Direction — Pinned
to LTR App-Wide": iOS discovered that RTL mirroring flips not just `.leading`/`.trailing`-based
layout but was observed to flip raw `.offset(x:)`-based transitions too, and fixed it by pinning
`.environment(\.layoutDirection, .leftToRight)` on the whole root `WindowGroup` — "forward"
always means physically right regardless of device language.

**To do:**
- Replace `Alignment.CenterStart`/`CenterEnd` in `SwipeIndicator.kt` with explicit,
  layout-direction-independent positioning (`Alignment.CenterLeft`/`CenterRight`-equivalent —
  Compose has no such built-in constant, so this likely means computing the `Box` position
  manually via `Modifier.offset`/`align(Alignment.Center)` + a sign flip, or wrapping just the
  gesture/badge subtree in a forced `CompositionLocalProvider(LocalLayoutDirection provides
  LayoutDirection.Ltr)`).
- Audit `CardStackLayer.kt`'s drag-direction resolution (`resolveSwipeDirection`) and fling
  targets for the same class of bug — the drag math itself is already raw pointer-offset based
  (direction-agnostic per android/CLAUDE.md's own "Layout Direction" section), so it's likely
  fine, but confirm rather than assume once item 2's RTL work lands and this becomes testable
  end-to-end on a Hebrew-locale device.
- Re-verify on the physical device once fixed — this class of bug is easy to "fix" for the
  common LTR case while still being wrong under RTL if not tested on an actual Hebrew-locale
  device.

---

## 4. Main tab should default to Swipe, not Filters

`MainActivity.kt`'s `SwipyNavHost` has `startDestination = ROUTE_FILTERS` — the app currently
opens on the Smart Filters/Categories screen. iOS defaults to the Swipe tab
(`ContentView.swift`: `@State private var selectedTab = 1`, where tab 1 is `SwipeStackView`) —
Filters is reachable but not the landing screen.

**To do:**
- Change `startDestination` to `ROUTE_SWIPE` in `SwipyNavHost` (`MainActivity.kt`).
- Double-check `FilterCategoriesScreen`'s → `PhotoStackViewModel.LoadPhotos` → Swipe handoff
  still behaves correctly with Swipe as the "home" tab (it should — `navigateToTab` already
  fully clears the back stack per-tab, so this shouldn't require any other change), but verify
  after switching.

---

## 5. Smart Filters counts are inconsistent / don't make sense together

Observed on-device: **All Photos: 100**, while individual sub-category counts (e.g. Screenshots:
99+, Videos: 13, plus several more categories) clearly sum to well more than 100 in the real
library. Showing "All Photos: 100" reads as obviously wrong to a user who can see the individual
categories add up to more.

**Likely cause**: Phase 1 fast counts are capped at 100 for *every* category, `.All` included
(`FilterCategoriesViewModel`'s `CAP = 100`, `GetCategoryCountUseCase` — see android/CLAUDE.md
"Smart Filter Counting (2-Phase)"). This matches iOS's own documented behavior (the cap
"matches the '99+' display ceiling"), **but** iOS's UI only ever renders the `"99+"` collapsed
form for count >= 100 on every category *except* `.all`
(`SmartFiltersView.swift:190`: `count >= 100 && category != .all ? "99+" : "\(count)"`) — i.e.
iOS special-cases `.all` to likely need an **uncapped** real count, not a capped Phase-1
estimate, specifically because showing a bare capped number like "100" for the whole-library
category (with no "+") reads as a real, precise, small count — which is exactly the confusing
result reported here.

**To do:**
- Check iOS's actual `.all` count path in `PhotoLibraryService`/`PhotoStackViewModel` — confirm
  whether `.all` genuinely gets an uncapped real total there (likely, e.g. via
  `PHFetchResult.count`, which is O(1) — no enumeration cost) rather than the same
  candidate-pool Phase-1 cap the other categories use.
- Port whatever iOS actually does for `.all` specifically — likely: give `FilterCategory.All` an
  **uncapped** real count (Android's `PhotoRepository.totalCount(FilterCategory.All)` already
  exists and is used elsewhere for Shuffle's random-seek range — reuse it here instead of the
  capped `countForCategory` path for this one category), while every other category keeps the
  capped/`"99+"` Phase-1 behavior as-is.
- Re-verify the numbers read sensibly together on-device once fixed.

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
