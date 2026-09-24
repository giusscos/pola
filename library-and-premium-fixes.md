# Library freeze & premium unlock fixes

Status tracker for the two bugs investigated on 2026-09-24.

| Issue | Status |
|---|---|
| Library freezes / crashes on open | ✅ Fixed, verified on simulator (iPhone 17 Pro, iOS 27, 7 photos) · ⏳ confirm on device |
| Premium stays locked after purchase | ✅ Fixed in code · ⏳ confirm with a fresh purchase on device |

No SwiftData migration was needed. Every schema change since the SwiftData release (`packColorHex`, `frameFormatRaw`, `lensName`) is an optional or defaulted property, which SwiftData migrates automatically. User data was never the problem.

---

## 1. Library freezes, then crashes

### Symptoms
- Tapping the Library button freezes the app (and sometimes the whole phone), then iOS kills it.
- First debugger capture: `EXC_RESOURCE (RESOURCE_TYPE_MEMORY: high watermark memory limit exceeded) (limit=3376 MB)`, with the crashing thread inside CMPhoto (image decoding).
- Later runs: SIGKILL with no crash report, or a permanent hang ("Application is not responding").
- Once the hang was fixed, the Library still didn't open, SwiftUI logged `Cycle detected through attribute`, and no sheet (Library, Settings) could be presented.

### Root causes

**A. The camera preview re-entered SwiftUI's update (main cause).**
`CameraPreviewView` assigned `previewLayer.session = session` in `makeUIView` and again on every `updateUIView`. When the capture session is running, AVFoundation rebuilds its capture graph and spins a nested run loop until that's done (`AVRunLoopCondition _waitInMode` inside `-[AVCaptureSession _buildAndRunGraph:]`). Running that inside a SwiftUI graph update makes SwiftUI re-enter its own render. It logs "Cycle detected through attribute" (9 times at launch) and drops transactions, so presentations never finish.
Found by breaking on `AG::Graph::print_cycle` in lldb.

**B. The library's update loop fed back into itself (made A catastrophic).**
Since iOS 26, UIKit automatically observation-tracks `layoutSubviews`. SwiftUI calls `LibraryView.updateUIViewController` from inside the camera screen's `_UIHostingView.layoutSubviews`. There the library:
- assigned `entries`, which ran `applySnapshot`, which reconfigured **every** cell;
- replaced `navigationItem.titleView` with a brand-new stack view.

Those UIKit mutations invalidated the tracked layout pass, which ran `updateUIViewController` again, and so on forever. iOS 18 doesn't enable UIKit observation tracking by default, which is why this appeared on iOS 26+.

**C. Full-resolution decoding in every cell (why memory blew up).**
Each grid cell used `entry.image` (`UIImage(data:)` of the full camera JPEG, about 48 MB decoded). With B reconfiguring all cells in a loop, memory climbed past the 3.3 GB limit.

### Fixes

| File | Change |
|---|---|
| `pola/Views/CameraPreviewView.swift` | Attach the session only when it changes, and do it in `DispatchQueue.main.async` so it runs after SwiftUI's update pass. Mirroring is applied after attaching. |
| `pola/Views/LibraryView.swift` | `updateUIViewController` defers `setEntries` and the deep link to `DispatchQueue.main.async`, outside the tracked layout pass. |
| `pola/Views/LibraryViewController.swift` | New `setEntries(_:)` skips the update when nothing a cell displays has changed (a hash of id, caption, backText, showMap, filter, pack, color, frame format, video, development progress). The title view is built once and only its text and alignment change. Nav bar buttons refresh when the list switches between empty and non-empty (needed now that entries arrive after `viewDidLoad`). Cells use thumbnails. |
| `pola/Others/PolaroidEntry.swift` | New `thumbnail(maxPixelSize:)`: decodes directly at grid size with ImageIO (`CGImageSourceCreateThumbnailAtIndex`) and caches in an `NSCache` capped at 150 MB. Safe to key by `id` because `imageData` never changes after creation. |

### Verification (simulator, 7 photos)
- 0 "Cycle detected" lines at launch (was 9).
- The Library opens and reopens, shows "7 items", and scrolls.
- Detail view opens, and Back works.
- Select: checkmark, "1/7" subtitle and bottom toolbar appear; Cancel restores the grid.
- The "…" menu works, with Caption Font and Font Weight locked when not premium.
- Settings opens again.

---

## 2. Premium stays locked after purchase

### Symptoms
Real device, launched from Xcode with `onlineStore.storekit`: after buying, there's no welcome screen, the paywall stays, and features stay locked.

### Root cause
Console logs (`[Premium]` category) showed:
```
Purchase com.pola.premium.yearly verified, tx 7
Refreshed status: isPremium=false, product=none
```
The purchase succeeds and is verified, but `Transaction.currentEntitlements` doesn't list the active subscription. A repeat purchase fails with `ASDServerErrorDomain Code=3532` (already subscribed). `Product.SubscriptionInfo.status` does report the subscription as `.subscribed`.

A second problem: several refreshes run concurrently (the purchase, the `Transaction.updates` listener and `scenePhase == .active`), and whichever finished last wrote `isPremium`. A stale refresh could re-lock the app.

### Fixes (`pola/Managers/PremiumManager.swift`)
- After a verified purchase, if the refresh still says locked, unlock directly from the transaction when `revocationDate == nil` and it hasn't expired.
- `refreshPurchaseStatus()` falls back to the subscription status API (`subscription.status`, states `.subscribed` / `.inGracePeriod`) when `currentEntitlements` has no subscription.
- A refresh generation counter ensures only the most recently started refresh (or a direct unlock from a purchase) writes state.
- State updates go through a single `apply(_:)` helper.
- `os.Logger` diagnostics (subsystem `com.giusscos.pola`, category `Premium`): purchase outcome, verification errors, entitlements with expiry, subscription states and the final status.

### Verification
- ✅ On device, launch now resolves `isPremium=true, product=com.pola.premium.yearly` through the status API fallback.
- ⏳ **To do:** in Xcode, open Debug → StoreKit → Manage Transactions, delete Pola's transactions, run on device and buy again. Expected: the paywall switches to `PremiumWelcomeView` without a restart. If not, capture the `[Premium]` console lines.

---

## Open items

- [ ] Confirm the Library opens on the real device (larger library than the simulator).
- [ ] Confirm a fresh purchase unlocks the app without a restart (steps above).
- [ ] Decide whether to keep the `[Premium]` logging or trim it before release.
- [ ] Commit the changes on a branch (nothing committed yet).
- [ ] Low priority: 7 `CVPixelBufferCreate returned err -6680 (1008x756 RGBA)` log lines each time the Library opens. They don't freeze the app; the source hasn't been found yet.
- [ ] Low priority: after Cancel in select mode, the first cell keeps the "Selected" accessibility trait (the collection view's own selection isn't cleared).
- [ ] Low priority: `ContentView`'s library button thumbnail (`TimelineView` ticking every second) still decodes 2 full-resolution images per tick through `entry.image`. It could use `thumbnail(maxPixelSize:)`.

## Lessons for future changes

- Don't mutate UIKit views, or read and write `@Observable` / `@Model` state, synchronously inside `updateUIViewController` / `updateUIView` on iOS 26+. Defer the work or guard it against no-op updates.
- Never assign `AVCaptureVideoPreviewLayer.session` inside a SwiftUI update, and never assign it repeatedly.
- Grids must never decode full-resolution photos. Use `PolaroidEntry.thumbnail(maxPixelSize:)`.
- Don't rely on `Transaction.currentEntitlements` alone for subscriptions. Cross-check `subscription.status`, and trust the verified purchase result.
