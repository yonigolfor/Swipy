# Haptics — Swipy

Full map of every haptic event in the app: what fires, which generator, intensity, and timing.

---

## Swipe Actions

All swipe haptics are triggered in `PhotoStackViewModel` immediately when the swipe is committed, via `HapticService.shared`.

| Action | Method | Generator | Intensity | Pattern |
|--------|--------|-----------|-----------|---------|
| Swipe right (Keep) | `keep()` | light | default (~1.0) | single tap |
| Swipe left (Delete) | `delete()` | heavy | 0.8 | single tap |
| Swipe up (Snooze) | `snooze()` | light | 0.6 | single tap |
| Shake to undo | `undo()` | notification | — | `.success` |

**Design intent:** Delete is noticeably heavier than Keep — the asymmetry reinforces that deletion is a weightier action. Snooze is the lightest of the three, signalling deferral rather than decision.

---

## UI Actions

| Trigger | Method | Generator | Pattern |
|---------|--------|-----------|---------|
| Filter category tap | `selection()` | `UISelectionFeedbackGenerator` | `selectionChanged()` |
| Shuffle FAB tap | `shuffle()` | light | 0.7 single tap |
| Shuffled cards land | `shuffleLand()` | light | 0.5 → 120ms delay → 0.35 |
| Page load success (new stack page) | `success()` | notification | `.success` |

---

## Gamified Top Bar — GB Milestone (1000 MB)

When `sessionSpaceSavedMB` crosses a 1 GB boundary, `SessionSavingsBarView` fires `triggerHapticBurst()` — a 6-beat crescendo built directly with `UIImpactFeedbackGenerator` (not via `HapticService`, because this sequence doesn't map to a single swipe action pattern).

**Exception note:** `SessionSavingsBarView` is the only view allowed to use `UIImpactFeedbackGenerator` directly. All other views must go through `HapticService`.

| Beat | Generator | Intensity | Delay before beat |
|------|-----------|-----------|-------------------|
| 1 | medium | 0.7 | — |
| 2 | heavy | 0.9 | 85 ms |
| 3 | heavy | 1.0 | 85 ms |
| 4 | medium | 0.8 | 90 ms |
| 5 | heavy | 1.0 | 95 ms |
| 6 | notification `.success` | — | 70 ms |

**Timing context:** The burst fires ~360 ms after the bar visually fills to 100%, aligned with the start of the star's `PhaseAnimator` celebration cycle (windup → spin → settle).

---

## Review Bin — Item Restore (Poof Animation)

Fired in `ReviewGridItemView` at the exact moment the cell transitions from `.popping` → `.poofing` (Phase 2 of the restore animation), via SwiftUI's `.sensoryFeedback` modifier.

| Trigger | API | Feedback type | Intensity |
|---------|-----|---------------|-----------|
| Cell poof (restore) | `.sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: hapticTrigger)` | soft impact | 0.7 |

**Design intent:** A light, "bubble-pop" sensation matching the visual poof — the opposite of the heavy triple-beat used for permanent deletion. Uses `.sensoryFeedback` (iOS 17+ SwiftUI API) rather than `HapticService`, as it is a single-event visual-sync haptic local to the cell.

---

## Review Bin — Empty Trash

Fired in `PhotoStackViewModel.emptyTrash()` via `HapticService.emptyTrash()`.

| Beat | Generator | Intensity | Delay |
|------|-----------|-----------|-------|
| 1 | heavy | 1.0 | — |
| 2 | heavy | 1.0 | 100 ms |
| 3 | heavy | 1.0 | 200 ms |

Triple-heavy at full intensity — the strongest feedback in the app, matching the finality of permanent deletion.

---

## HapticService — Generator Pool

`HapticService` is a singleton that keeps pre-warmed generator instances to minimise first-fire latency:

```swift
private let lightGenerator    = UIImpactFeedbackGenerator(style: .light)
private let mediumGenerator   = UIImpactFeedbackGenerator(style: .medium)
private let heavyGenerator    = UIImpactFeedbackGenerator(style: .heavy)
private let selectionGenerator = UISelectionFeedbackGenerator()
private let notificationGenerator = UINotificationFeedbackGenerator()
```

All generators call `.prepare()` on `init` and again after each `impactOccurred()` call to stay warm for the next swipe.

---

## Adding New Haptics

1. Add a method to `HapticService.swift` — never call `UIImpactFeedbackGenerator` directly from a view.
2. The only exception is self-contained celebration sequences (like `triggerHapticBurst`) where the timing logic lives entirely inside one component.
3. Call from the ViewModel (swipe actions) or from the View itself (UI feedback like shuffle).
4. Always call `.prepare()` after `.impactOccurred()` so the next event doesn't stutter.
