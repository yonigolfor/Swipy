# Share Feature — Architecture & Design Decisions

## Overview

Swipy supports sharing any photo or video directly from the swipe card stack. Tapping the share button (top-right of the top card) opens the native iOS share sheet immediately, then begins downloading the asset only after the user picks a destination app.

---

## Core Design: Deferred Download via UIActivityItemProvider

The share sheet opens instantly — no waiting for iCloud downloads.

`UIActivityItemProvider` defers the actual asset fetch to the moment the user selects a destination. Until then the provider's `item` getter hasn't been called at all. This is critical for iCloud assets where network download can take seconds.

Both `ImageItemProvider` and `VideoItemProvider` follow the same pattern:
1. Share sheet opens immediately (`isShowingShareSheet = true`)
2. User picks destination — iOS calls `item` on a dedicated UIKit background thread
3. `item` downloads the asset via `PHAssetResourceManager.requestData`, updates the HUD, returns the file

---

## Asset Download: PHAssetResourceManager.requestData

Both providers use `PHAssetResourceManager.requestData(for:options:dataReceivedHandler:completionHandler:)` instead of the higher-level `PHImageManager` APIs.

**Why:**
- Returns a `PHAssetResourceDataRequestID` → true cancellation via `cancelDataRequest(_:)`
- Fires `progressHandler` with 0→1 progress → drives the HUD ring
- Writes raw file bytes (no UIImage decompression overhead) → faster, especially for large/iCloud assets
- Works identically for images and videos → single unified pattern

**Temp file assembly:**
```
FileManager.createFile → FileHandle(forWritingTo:)
  dataReceivedHandler → fileHandle.write(contentsOf: chunk)
  completionHandler  → fileHandle.synchronize() + closeFile()
```
The temp file lives at `NSTemporaryDirectory()` with a `UUID()` filename preserving the original extension. It is deleted in `deinit`.

---

## Cancellation: DispatchSemaphore + cancelDataRequest

`item` blocks on `DispatchSemaphore.wait()` while the download runs. Cancellation works from any thread:

```
cancel() called
  → super.cancel()                          // sets isCancelled = true (Operation)
  → cancelDataRequest(requestID)            // stops network transfer immediately
  → semaphore.signal()                      // unblocks sem.wait() in item
item resumes, checks isCancelled → returns placeholderItem
```

The semaphore may receive a double-signal if `cancel()` and the completion handler both fire (e.g., cancel arrives just as download completes). This is safe — the extra signal accumulates in the semaphore and is never consumed.

---

## HUD: ShareHUDManager + ShareHUDView

A floating `UIWindow` at `.alert + 1` level sits above all other UI including the system share sheet. This level is required because the share sheet itself is presented at `.alert`, so a standard view overlay would be hidden behind it.

### ShareHUDManager (Service)
- Singleton `@MainActor` class — all UIWindow mutations on main thread
- Creates a `UIHostingController<ShareHUDView>` as the window's root VC
- Background is `UIColor.clear`; `ShareHUDView` renders `.ultraThinMaterial` only for the card itself
- Plain `UIWindow` (not a PassthroughWindow) — `Color.clear` areas return `nil` from `hitTest` automatically, so the cancel button receives taps correctly without any custom hit-testing

### ShareHUDView (Component)
- Circular progress ring using `Circle().trim(from: 0, to: progressFraction)` 
- `animationPhase: Int` (0–3) drives layout animations; raw progress ticks do NOT trigger layout re-renders (prevents `.animation` from refiring on every tiny progress update)
- Ring → green checkmark transition on `.complete`
- Cancel button styled as a `Capsule` (visually distinct as an interactive element)

### Phase flow
```
UIActivityItemProvider.item starts
  → onPhaseChange(.downloading(0))   → phase pre-set; 1.5s HUD-show Task starts
  → progressHandler fires             → onPhaseChange(.downloading(0.0...1.0)) → phase updates (window may not exist yet)
  → completionHandler fires           → onPhaseChange(.processing)              → "Processing..."
  → item returns the asset            → onPhaseChange(.complete)               → success haptic; HUD cancel task
                                                                               → if HUD is visible: checkmark → 600ms → hide
                                                                               → if HUD not yet visible: Task cancelled, no window ever created
```

### HUD Debounce (1.5s threshold)

Fast local assets complete in under 200ms — showing a HUD that immediately dismisses is jarring. The window is created only if the download is still in progress after 1.5 seconds:

- **< 1.5s**: `.complete` fires → `hudShowTask.cancel()` → HUD never appears; success haptic fires silently
- **≥ 1.5s**: `hudShowTask` fires → `show()` is called with the current phase (already at live progress, not 0%) → normal HUD lifecycle

The phase is pre-set to `.downloading(0)` immediately when the download starts (before the 1.5s delay) so the ring renders at the correct live progress value when the window opens, rather than jumping from 0%.

`hudShowTask` is cancelled in three places: `.complete` arriving early, `cancelShare()`, and at the start of any new `shareItem()` call (implicit via the `isShowingShareSheet` guard).

---

## Thumbnail Pre-loading (Freeze Prevention)

`activityViewControllerLinkMetadata(_:)` is called on the **main thread** to populate the share sheet header (title + thumbnail). Any blocking work here deadlocks the UI.

Both providers pre-load the thumbnail in `init` on `DispatchQueue.global(qos: .userInitiated)` using `PHImageManager` with `isSynchronous: true` and `deliveryMode: .fastFormat`. The thumbnail is stored as a property and returned synchronously from `activityViewControllerLinkMetadata`. This is safe because `init` completes before the share sheet first calls the method.

---

## ViewModel Integration

```swift
// PhotoStackViewModel
private weak var currentProvider: UIActivityItemProvider?

func shareItem(_ item: PhotoItem, completion: @escaping () -> Void)
func cancelShare()
```

`currentProvider` is `weak` — the provider is kept alive by `shareItems: [Any]` which is what SwiftUI passes to `UIActivityViewController`. When the share completes or is cancelled, the provider is released from `shareItems` automatically.

`shareItem()` guards against concurrent shares with `isPreparingShareRequest` (blocks re-entry during setup) and `isShowingShareSheet` (blocks while sheet is visible).

`cancelShare()` is called from the HUD's cancel button via `ShareHUDManager.triggerCancel()` → `cancelAction` closure → `viewModel.cancelShare()`.

---

## Files

| File | Role |
|------|------|
| `Services/ShareHUDManager.swift` | `SharePhase` enum + `ShareHUDManager` UIWindow service |
| `Views/Components/ShareHUDView.swift` | SwiftUI HUD hosted in the ShareHUDManager window |
| `ViewModels/PhotoStackViewModel.swift` | `shareItem()`, `cancelShare()`, `ImageItemProvider`, `VideoItemProvider` |
| `Views/Main/PhotoCardView.swift` | Share button (top card only) + `isSharing` spinner state |
| `Views/Main/SwipeStackView.swift` | `ActivityView` wrapper + `.sheet(isPresented:)` presentation |
| `Localizable.xcstrings` | `share.hud.cancel`, `share.hud.downloading`, `share.hud.processing`, `share.hud.complete`, `share.caption` |
