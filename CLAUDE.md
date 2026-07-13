# Pola — Claude Code Project Prompt

## Minimum OS Version

**Deployment target: iOS 18.0**

The app must build and run on iOS 18.0 and later. This is the hard minimum; do not use APIs that require iOS 26 or higher without wrapping them in an `#available(iOS 26, *)` guard and providing a fallback.

> Note: Apple's versioning jumps directly from iOS 18 to iOS 26 — there is no iOS 19, 20, 21, 22, 23, 24, or 25.

### Rules

- All new code must compile and run on iOS 18.0 without any `#available` guard.
- APIs introduced in iOS 26 or later **must** be wrapped:
  ```swift
  if #available(iOS 26, *) {
      // new API
  } else {
      // iOS 18-compatible fallback
  }
  ```
- The `preferredTransition` / zoom transition in `LibraryViewController` is already correctly gated with `#available(iOS 18.0, *)` — keep that guard in place if the deployment target is ever raised above 18.
- Remove any `#available` guards for iOS versions **below** 18 (e.g. the `#available(iOS 16.0, *)` block in `CameraManager`) since those APIs are now always available.

### Xcode project

- `IPHONEOS_DEPLOYMENT_TARGET` in `project.pbxproj` must be `18.0` for all configurations (Debug and Release, app target and any extension targets).
- The current value is set to `26.0` / `26.5` — update these before shipping.

## Architecture

- Language: Swift + SwiftUI with UIKit where needed (e.g. `LibraryViewController`)
- State: SwiftData (`@Model`, `ModelContext`) — no CoreData
- Camera: AVFoundation via `CameraManager`
- No Combine — use Swift `async`/`await` and `@Observable`
- Premium gating: `PremiumManager`

## Code Style

- PascalCase types, camelCase properties/methods
- 4-space indentation
- No force-unwraps; prefer `guard let` / `if let`
- Write comments only when the *why* is non-obvious
