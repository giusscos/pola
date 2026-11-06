# Poly 1.0.8 — App Store release kit

A feature-only update: the app changes, the store listing doesn't. App Name, Subtitle, Keywords, Description, Promotional Text, screenshots and In-App Purchases stay exactly as in 1.0.7 (`../1.0.7/`). Only **What's New** is new, in each language file here and in `whats-new/`.

Check limits after any edit:
```bash
python3 app-store/check_lengths.py app-store/1.0.8
```

- **Version:** `MARKETING_VERSION` 1.0.8 for the app and the widget. Builds come from Xcode Cloud after a push to `main`.
- **Go-live date:** _not live yet_

## What's in it

| Change | Where |
|---|---|
| Notification 2 days before a free trial ends; the paywall says so | `TrialReminder`, `PaywallView` |
| Review prompt after 3 photos (was 7), never within 5 minutes of a paywall | `ReviewPrompter` |
| Settings → Rate the App opens the App Store's review page | `SettingsView` |
| Camera access denied: explanation and an Open Settings button | `ContentView`, `CameraManager` |
| Camera screen's library button uses cached thumbnails | `ContentView` |
| Products reload if the launch load failed | `PremiumManager`, `PaywallView` |
| After buying Lifetime while subscribed: prompt to cancel the subscription | `SettingsView` |
| Settings shows "Free trial · ends …, then …" | `SettingsView` |
| Ask to Buy and other pending purchases show a waiting message | `PremiumManager`, `PaywallView` |

The in-app What's New sheet stays on 1.0.7 (`WhatsNew.version`), so people updating from 1.0.7 don't see it again.

## Before submitting

- [x] Tested on an iPhone 15 Pro (Release build of the same commit, sandbox account), Nov 6, 2026: start the yearly trial and allow notifications. The console shows "Trial reminder scheduled for …", about 5 days ahead.
- [x] Buy Lifetime while subscribed: the "Lifetime unlocked" alert opens Manage Subscription.
- [x] Deny camera access: Open Settings appears and works.
- [x] Version 1.0.8 created in App Store Connect (Nov 6, 2026). What's New is pasted in all 5 languages. Promotional Text came over empty, so the 1.0.7 "trial live" text was pasted back in all 5 languages.
- [x] Xcode Cloud build 8 (1.0.8) selected. It's also in TestFlight internal testing.
- [x] Submitted for review on Nov 6, 2026. Release setting: automatically after approval, as in 1.0.7.
