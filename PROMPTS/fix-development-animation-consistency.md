# Fix: Polaroid Development Animation Inconsistency Across Views

## Problem

The polaroid "developing" animation (black overlay fading to the full photo over 30 seconds) is not consistent across views. If the user shakes the polaroid to speed up development — either in the **camera print animation** or in the **detail view** — the accelerated progress is not reflected when switching to:

- **Library list view** — the polaroid still appears nearly fully black, as if no shaking happened.
- **Detail view** — after the camera shook the photo forward, opening the detail view resets progress back to time-only (ignoring the shake advancement).

## Root Cause

### How development works

`PolaroidEntry.developmentProgress` (a `Double` in SwiftData, range 0–1) is meant to be the authoritative stored progress value. Each view has its own animation strategy:

| View | Strategy | Driver |
|---|---|---|
| Camera `PolaroidPrintAnimationView` | `animatedExternally: true` | Camera manager / shake stores into `entry.developmentProgress` |
| Detail `PolaroidDetailViewController` | `animatedExternally: entry.developmentProgress < 1.0` | `CADisplayLink tickDevelopment()` — ticks `entry.developmentProgress` via `timestamp + shakeBonus` |
| Library list `LibraryViewController` | `animatedExternally: false` (default) | `PolaroidPhotoCell.onAppear` — internal `localReveal` driven purely by `timestamp` |

### Bug 1 — Library list ignores stored `developmentProgress`

In `LibraryViewController.configure(cell:forID:)` (line 153–189), `animatedExternally` is never set, so it defaults to `false`. Inside `PolaroidPhotoCell.init`, when `animatedExternally == false` and `developmentProgress < 1.0`, the starting `localReveal` is computed **only from elapsed time**:

```swift
// PolaroidPhotoCell.swift — init, line 167-169
} else if let ts = timestamp {
    let elapsed = Date().timeIntervalSince(ts)
    self._localReveal = State(initialValue: min(1.0, elapsed / 30.0))
}
```

This completely ignores the stored `developmentProgress`. If the camera shake advanced the photo to `0.9` after only 3 seconds, the library cell re-initialises `localReveal` to `3/30 = 0.1` — nearly black.

The `onAppear` handler (line 209–224) then animates over the full remaining time based on `timestamp`, again ignoring any shake bonus.

### Bug 2 — Detail view overwrites shake-advanced progress on entry

In `PolaroidDetailViewController.manageDevelopment()` (line 98–130), when the view appears for a still-developing entry it seeds progress from raw elapsed time:

```swift
// PolaroidDetailViewController.swift — manageDevelopment(), line 114
entry.developmentProgress = min(1.0, elapsed / 30.0)
```

This unconditionally overwrites whatever shake-advanced value was stored, potentially going *backwards* (e.g. stored `0.9` → overwritten with `0.17`).

Then `tickDevelopment()` (line 132–148) recomputes progress as:

```swift
let elapsed = Date().timeIntervalSince(entry.timestamp) + shakeBonus
let progress = min(1.0, elapsed / 30.0)
entry.developmentProgress = progress
```

`shakeBonus` starts at `0` when the detail view opens, so the tick keeps pushing `developmentProgress` down towards the time-based value for the first several seconds.

## Fix Strategy

`developmentProgress` in SwiftData must be treated as a **monotonically increasing floor**: no view may set it to a value lower than its current stored value. When computing remaining animation time, always derive it from `developmentProgress` (the highest known progress) rather than purely from elapsed time.

### 1. Fix `PolaroidPhotoCell` init — use stored progress as the floor

In `PolaroidPhotoCell.swift`, the init block that seeds `localReveal` (line 165–173) should use the maximum of stored progress and time-based progress:

```swift
// Replace:
} else if let ts = timestamp {
    let elapsed = Date().timeIntervalSince(ts)
    self._localReveal = State(initialValue: min(1.0, elapsed / 30.0))
}

// With:
} else if let ts = timestamp {
    let elapsed = Date().timeIntervalSince(ts)
    let timeBased = min(1.0, elapsed / 30.0)
    self._localReveal = State(initialValue: max(developmentProgress, timeBased))
}
```

### 2. Fix `PolaroidPhotoCell.onAppear` — derive remaining time from `localReveal`

The `onAppear` handler (line 209–224) should compute remaining time from the *current* `localReveal` (which now starts from the higher of stored or time-based), not from raw elapsed time:

```swift
// Replace:
.onAppear {
    guard !animatedExternally, localReveal < 1.0, let ts = timestamp else { return }
    let elapsed = Date().timeIntervalSince(ts)
    let remaining = max(0, 30.0 - elapsed)
    guard remaining > 0 else {
        localReveal = 1.0
        onDeveloped?()
        return
    }
    withAnimation(.linear(duration: remaining)) {
        localReveal = 1.0
    }
    Task {
        try? await Task.sleep(for: .seconds(remaining))
        onDeveloped?()
    }
}

// With:
.onAppear {
    guard !animatedExternally, localReveal < 1.0 else { return }
    let remaining = 30.0 * (1.0 - localReveal)
    guard remaining > 0 else {
        localReveal = 1.0
        onDeveloped?()
        return
    }
    withAnimation(.linear(duration: remaining)) {
        localReveal = 1.0
    }
    Task {
        try? await Task.sleep(for: .seconds(remaining))
        onDeveloped?()
    }
}
```

Note: the `timestamp` guard can be dropped here since `localReveal` is now authoritative.

### 3. Fix `PolaroidDetailViewController.manageDevelopment()` — seed `shakeBonus` from stored progress

In `manageDevelopment()`, instead of overwriting `entry.developmentProgress` with the time-based value, seed `shakeBonus` so the display link starts from the stored (potentially shake-advanced) value:

```swift
// Replace:
// Seed progress from elapsed time so the veil reflects real time
entry.developmentProgress = min(1.0, elapsed / 30.0)

// With:
// Seed shakeBonus from stored progress so we never go backwards.
// Stored progress may be ahead of real time (due to prior shaking).
let storedProgress = entry.developmentProgress
shakeBonus = max(0, storedProgress * 30.0 - elapsed)
entry.developmentProgress = max(storedProgress, min(1.0, elapsed / 30.0))
```

### 4. Fix `PolaroidDetailViewController.tickDevelopment()` — never go below stored progress

As a safety net, prevent the display link from ever lowering `entry.developmentProgress`:

```swift
// Replace:
let progress = min(1.0, elapsed / 30.0)
CATransaction.begin()
CATransaction.setDisableActions(true)
entry.developmentProgress = progress

// With:
let progress = min(1.0, elapsed / 30.0)
CATransaction.begin()
CATransaction.setDisableActions(true)
entry.developmentProgress = max(entry.developmentProgress, progress)
```

## Expected Behaviour After Fix

- Shaking a polaroid to 90% in the camera view, then navigating to the library list, should show the photo at ~90% revealed (not ~10% based on timestamps alone).
- Opening the detail view for a shake-advanced photo should continue development from where it was left, not reset to the time-based baseline.
- Shaking in the detail view should still work as before, and the progress should persist correctly when navigating back to the library.
- Photos that have fully developed (`developmentProgress == 1.0`) remain unaffected in all views.

## Files to Edit

| File | Lines affected |
|---|---|
| `pola/Views/PolaroidPhotoCell.swift` | `init` (lines 165–173), `onAppear` (lines 209–224) |
| `pola/Views/PolaroidDetailViewController.swift` | `manageDevelopment()` (line 114), `tickDevelopment()` (line 137) |
