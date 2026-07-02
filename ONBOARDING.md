# Onboarding Flow — Reference Doc

Single file: `Swipy/Views/OnboardingView.swift`  
Gate: `hasCompletedOnboarding` in `UserDefaults` — `SplashScreenView` checks this; `onComplete()` sets it to `true`.

---

## Architecture

`OnboardingView` is a single SwiftUI struct. All steps are **computed properties** (`private var step*: some View`) switched over `@State private var currentStep: Int`.

```swift
Group {
    switch currentStep {
    case 0: step1_VisualHook
    case 1: step2_Scan
    case 2: step3_SwipeDemo
    case 3: step4_Permission
    case 4: step5_QuickWin
    case 5: step_SnoozeIntro
    default: EmptyView()
    }
}
.transition(.asymmetric(
    insertion: .move(edge: .trailing).combined(with: .opacity),
    removal:   .move(edge: .leading).combined(with: .opacity)
))
.id(currentStep)   // ← forces SwiftUI to tear down + re-insert on every step change
```

**Important:** case numbers ≠ display order. See flow below.  
Step changes always use `.spring(response: 0.4, dampingFraction: 0.75)`.

---

## Display Order (User Experience)

| Display # | `currentStep` | Step name | Hebrew name | Next target |
|-----------|--------------|-----------|-------------|-------------|
| 1 | `0` | `step1_VisualHook` | הטלפון שלך סוחב משקל מיותר | → `3` |
| 2 | `3` | `step4_Permission` | כדי שנוכל לעשות את הקסם | → `2` (via permission request) |
| 3 | `2` | `step3_SwipeDemo` | ניקוי בסטייל | → `5` |
| 4 | `5` | `step_SnoozeIntro` | לא בטוח? אין בעיה | → `1` |
| 5 | `1` | `step2_Scan` | סורק את הגלריה | → `4` |
| 6 | `4` | `step5_QuickWin` | הכל מוכן! | → `onComplete()` |

---

## Each Step

### step1_VisualHook (`case 0`)
**Localization prefix:** `onboarding.hook.*`

- **Visual:** Z-stacked `RoundedRectangle`s (5 shadow cards) + top card with `photo.stack.fill` SF Symbol and "10,000+" text
- **Cards:** `width: 220, height: 280`, `cornerRadius: 20`, gradient fill `Color(white: 0.25…0.18)`, rotated ±12° fan
- **CTA:** Gold gradient capsule → jumps directly to `currentStep = 3` (Permission)

---

### step4_Permission (`case 3`)
**Localization prefix:** `onboarding.permission.*`

- **Visual:** `lock.shield.fill` SF Symbol (size 60) inside a blue-tinted circle (`Color.blue.opacity(0.15)`, frame 120×120)
- **Icon gradient:** `.blue → .cyan`, top → bottom
- **Privacy bullets:** 3 rows via `privacyRow(icon:text:)` — icons in `.green`, text `.white.opacity(0.8)`, `.subheadline`
  - `iphone` — stays on device
  - `eye.slash.fill` — private
  - `trash.slash.fill` — you're in control
- **CTA:** calls `requestPermission()` which:
  1. Calls `PHPhotoLibrary.requestAuthorization(for: .readWrite)`
  2. Immediately advances to `currentStep = 2` (SwipeDemo)
  3. Calls `viewModel.startOnboardingScan()` in background — scan runs while user goes through demo

---

### step3_SwipeDemo (`case 2`)
**Localization prefix:** `onboarding.demo.*`

- **Visual:** Interactive draggable card (`width: 240, height: 300`, same gradient style as VisualHook) + shadow card behind
- **Drag behavior:**
  - `demoOffset` + `demoRotation` track `DragGesture`
  - Threshold > 80pt → card flies off, resets after 0.6s
  - Label overlay: "DELETE" in `.swipeRed` / "KEEP" in `.swipeGreen`, rotated ±15°
  - `softHaptic` on every drag change, `haptic` on release
- **State vars:** `demoOffset`, `demoRotation`, `demoCardVisible`, `demoLabel`
- **CTA:** → `currentStep = 5` (SnoozeIntro)

---

### step_SnoozeIntro (`case 5`)
**Localization prefix:** `onboarding.snooze.*`

- **Visual:** Same dark card (240×300) with 🤔 emoji (size 72) + `arrow.up.circle.fill` SF Symbol (size 38) in `.swipeBlue`
- **Animation:** Arrow bounces up/down 10pt via `snoozeAnimateArrow` state + `.easeInOut(duration: 0.7).repeatForever(autoreverses: true)`
  - Started with `.task { try? await Task.sleep(for: .milliseconds(150)) }` — avoids ambient transaction bleed from step transition
- **Subtitle color:** `.swipeBlue` = `Color(red: 0.25, green: 0.55, blue: 0.95)`
- **CTA:** → `currentStep = 1` (Scan)

---

### step2_Scan (`case 1`)
**Localization prefix:** `onboarding.scan.*`

- **Visual:** Glassmorphic card (`.ultraThinMaterial` + `strokeBorder(Color.white.opacity(0.15))`, `cornerRadius: 24`, padding 24)
- **Content:** 3 scan rows via `scanRow(icon:label:value:isScanning:color:)`:
  - `photo.fill` — Photos — `.blue`
  - `video.fill` — Videos — `.purple`
  - `film.fill` — Large Videos — `.orange`
- **Scanning state:** `ScanningDotsView` (3 pulsing circles, color-matched) shows while value == 0 and scan not complete
- **Animated counters:** `displayedPhotoCount / Video / Large` animate via `animateScanCounts()` — 20 steps × 55ms
- **Scan complete indicator:** `checkmark.circle.fill` in `.green` fades in on the header
- **Two CTAs:**
  - Gold capsule (appears when `viewModel.onboardingScanComplete == true`) → `currentStep = 4`
  - Gray "Skip" text button (visible while scanning) → `currentStep = 4`
- **Triggers:** `.onAppear` + `.onChange(of: viewModel.onboardingPhotoCount)` to animate counters when data lands

---

### step5_QuickWin (`case 4`)
**Localization prefix:** `onboarding.quickwin.*`

- **Visual:** `checkmark.seal.fill` (size 80) in `.green`, two concentric green-tinted circles (140pt + 180pt)
- **Shadow:** `.green.opacity(0.5)`, radius 20
- **CTA:** calls `onComplete()` — sets `hasCompletedOnboarding = true` and shows `ContentView`

---

## Shared Design Tokens

### Background
```swift
Color(red: 0.08, green: 0.08, blue: 0.10)   // #141417 — matches SplashScreenView
```

### CTA Button (all steps)
```swift
Capsule()
    .fill(LinearGradient(
        colors: [Color(red: 1, green: 0.85, blue: 0.3),   // gold
                 Color(red: 1, green: 0.65, blue: 0.1)],  // amber
        startPoint: .leading, endPoint: .trailing
    ))
// Shadow:
.shadow(color: Color(red: 1, green: 0.7, blue: 0.2).opacity(0.5), radius: 15, y: 5)
// Label:
.font(.headline).foregroundColor(.black)
.padding(.vertical, 18).padding(.horizontal, 32).padding(.bottom, 48)
```

### Typography
| Role | Style |
|------|-------|
| Main title | `.system(size: 32, weight: .bold, design: .rounded)` |
| Permission title | `.system(size: 28, weight: .bold, design: .rounded)` |
| QuickWin title | `.system(size: 36, weight: .bold, design: .rounded)` |
| Snooze subtitle | `.title3 + .fontWeight(.bold)` in `.swipeBlue` |
| Subtitles / body | `.subheadline` in `.gray` |
| Privacy bullets | `.subheadline` in `.white.opacity(0.8)` |
| Skip button | `.subheadline` in `.gray` |

### Cards (demo + snooze visual)
```swift
RoundedRectangle(cornerRadius: 20)
    .fill(LinearGradient(
        colors: [Color(white: 0.28), Color(white: 0.20)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    ))
    .frame(width: 240, height: 300)
    .shadow(color: .black.opacity(0.4), radius: 15, y: 8)
// Shadow card behind:
RoundedRectangle(cornerRadius: 20).fill(Color(white: 0.18))
    .frame(width: 240, height: 300).offset(y: 10).scaleEffect(0.95)
```

### Haptics
- `UIImpactFeedbackGenerator(style: .medium)` — all CTA taps
- `UIImpactFeedbackGenerator(style: .soft)` — SwipeDemo drag changes

---

## State Variables

| Variable | Type | Used by |
|----------|------|---------|
| `currentStep` | `Int` | router — drives the switch |
| `displayedPhotoCount` | `Int` | Scan — animated counter |
| `displayedVideoCount` | `Int` | Scan — animated counter |
| `displayedLargeCount` | `Int` | Scan — animated counter |
| `demoOffset` | `CGSize` | SwipeDemo — card drag position |
| `demoRotation` | `Double` | SwipeDemo — card tilt |
| `demoCardVisible` | `Bool` | SwipeDemo — hide/re-show card after fly-off |
| `demoLabel` | `String?` | SwipeDemo — KEEP / DELETE label overlay |
| `snoozeAnimateArrow` | `Bool` | SnoozeIntro — triggers arrow bounce animation |

---

## Localization Keys

All keys follow the pattern `onboarding.<step>.<element>`. Both `en` and `he` translations exist in `Localizable.xcstrings`.

| Key | EN value |
|-----|----------|
| `onboarding.hook.title` | "Your phone is carrying\nunnecessary weight." |
| `onboarding.hook.subtitle` | (tagline) |
| `onboarding.hook.cta` | "Get Started" |
| `onboarding.permission.title` | "כדי שנוכל לעשות את הקסם" |
| `onboarding.permission.subtitle` | "We need access to your gallery.\nEverything stays on your device only 🔒" |
| `onboarding.permission.cta` | "Grant Access to Gallery" |
| `onboarding.permission.local` | on-device privacy bullet |
| `onboarding.permission.private` | private bullet |
| `onboarding.permission.control` | control bullet |
| `onboarding.demo.title` | "Cleanup in style." |
| `onboarding.demo.subtitle` | "Left to trash, right to keep." |
| `onboarding.demo.hint` | "Try dragging the card" |
| `onboarding.demo.cta` | "Got it!" |
| `onboarding.snooze.title` | "Not Sure? No Problem" |
| `onboarding.snooze.subtitle` | "Swipe UP to snooze!" |
| `onboarding.snooze.body` | "We will show it to you later, so you can keep swiping!" |
| `onboarding.snooze.cta` | "Next" |
| `onboarding.scan.title` | "Scanning your gallery…" |
| `onboarding.scan.photos` | "Photos" |
| `onboarding.scan.videos` | "Videos" |
| `onboarding.scan.large_videos` | "Large Videos" |
| `onboarding.scan.privacy` | privacy note |
| `onboarding.scan.cta` | "Let's Clean Up!" |
| `onboarding.scan.skip` | "Skip for now" |
| `onboarding.quickwin.title` | "You're all set!" |
| `onboarding.quickwin.subtitle` | (encouragement) |
| `onboarding.quickwin.cta` | "Start Swiping" |

---

## Adding a New Step — Checklist

1. Add a new `case N:` in the `switch` and a `private var stepN_*: some View` computed property
2. Update the previous step's button to target `currentStep = N`
3. Update the new step's button to target the next `currentStep`
4. If the step has animation state, add a `@State private var` to `OnboardingView`
5. Use `.task { try? await Task.sleep(for: .milliseconds(150)); animate = true }` for `repeatForever` animations — never `onAppear` directly (avoids ambient transaction bleed from step transition)
6. Increment `totalSteps`
7. Add localization keys (`onboarding.<stepname>.*`) to `Localizable.xcstrings` with both `en` and `he` translations
