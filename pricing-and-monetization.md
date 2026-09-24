# poly. — Pricing & Monetization Backlog

Parked on purpose: everything here changes **what people pay** or needs App Store Connect / Xcode work outside the code. The conversion and UX work that didn't touch prices shipped on the `claude/conversion-ux-improvements-06632c` branch (see "Already shipped" at the bottom).

Current catalogue (`pola/offlineStore.storekit`):

| Product | ID | Price | Notes |
|---|---|---|---|
| Monthly | `com.pola.premium.monthly` | €2.99 | auto-renewable, group "Premium" |
| Yearly | `com.pola.premium.yearly` | €19.99 | auto-renewable, pre-selected on paywall |
| Lifetime | `com.pola.premium.lifetime` | €29.99 | non-consumable |

---

## 1. Free trial on Yearly — code shipped, needs App Store Connect

The paywall is ready. It checks eligibility with `isEligibleForIntroOffer`. When the selected plan has an eligible free trial, it shows a "7 DAYS FREE" badge, the button reads **"Try 7 days free"**, and the line under it reads *"7 days free, then $19.99/year. Cancel anytime."* (Guideline 3.1.2). Until the offer exists in App Store Connect, the paywall looks exactly as it does today.

**To switch it on:**
1. App Store Connect → Subscriptions → Yearly → Introductory Offers → Free, 1 week, all territories.
2. Re-sync `onlineStore.storekit` in Xcode (Editor → Sync). `offlineStore.storekit` already has the trial for local testing; point the scheme at it to try the flow.
3. Optional, not built: a local notification 2 days before the trial ends, which reduces refunds.

## 2. Price anchoring on the paywall — shipped

The yearly card shows **"$1.67/mo · save 44%"**, computed from the storefront prices, so it's correct in every currency. Monthly shows "Billed monthly" and Lifetime "One-time purchase". The line under the button always states what will be charged.

## 3. Lifetime price

**Problem:** Lifetime (€29.99) is only 1.5× Yearly (€19.99). Anyone planning to keep the app for more than 18 months should buy Lifetime, so it takes buyers away from recurring revenue.

**Options (pick one and test it):**
- Raise Lifetime to **€39.99–49.99** (2–2.5× yearly is the common range).
- Or keep the price but move Lifetime behind a *"More options"* link on the paywall so Yearly is the obvious choice.
- Keep the "Upgrade to Lifetime" row in Settings for existing subscribers either way. It's already shipped and it's the right place for that offer.

## 4. Win-back offers for lapsed subscribers

- Configure a **win-back offer** in App Store Connect (iOS 18+). For example, 50% off the first year for people whose subscription expired more than 30 days ago.
- The system shows it through `StoreKit.Message`. Observe `Message.messages` and present it at a calm moment, such as app launch with no capture in progress.
- Also consider a **promotional offer** (signed on your server) for people who cancel auto-renew. Needs a backend for signatures.

## 5. Offer codes

- Add a "Redeem Code" row in Settings → Premium (`.offerCodeRedemption(isPresented:)`).
- Use codes for influencer partnerships and press. Cheap to add, but it's a marketing channel decision.

## 6. Paywall experiments (only if you later add a way to measure them; App Store Connect conversion data works without an SDK)

| Experiment | Variants | Metric |
|---|---|---|
| Milestone paywall timing | after 3rd vs 5th photo | trial/purchase rate per install |
| Onboarding paywall | hard (no "Continue for Free" for 3 s) vs current | install → paid, D7 retention |
| Free filter | SOLVA vs FLÄRN vs none | install → paid |
| Plan order | Yearly first vs Monthly first | yearly share of purchases |

The free filter and free frame are one flag each (`isFree:` in `FiltersView.swift`), so this experiment is cheap to set up.

---

## Non-pricing items deferred (need Xcode / accounts / design)

### Analytics backend — not planned
Decided against a third-party analytics service. `pola/Managers/Analytics.swift` only writes to the device log (`log stream --predicate 'subsystem == "com.pola"'`), which is useful when debugging on a device, and sends nothing off it.

### Home-screen widget — shipped
The "Memories" widget comes in small and medium sizes and is a Premium feature; free users see a locked teaser that opens the paywall. Instead of moving the SwiftData/CloudKit store, the app writes a snapshot to the App Group `group.com.giusscos.pola`: up to 60 thumbnails plus `snapshot.json`, via `MemoryWidgetExporter`. It does this when the app goes to the background and when premium status changes. The widget shows photos from "on this day" in earlier years first, otherwise it rotates through the library every 3 hours. Tapping it opens that polaroid.
**Before shipping:** open the project in Xcode once with your account signed in so automatic signing registers the App Group and the `com.giusscos.pola.PolyWidget` bundle ID. Also keep `MARKETING_VERSION` of `PolyWidgetExtension` in sync with the app when you bump versions.

### Frame formats — shipped
Classic, Square (SX-70), Wide and Mini, set with `FrameFormat` in `Shared/`. They're picked in Filters → Format (Premium, except Classic), stored per polaroid (`frameFormatRaw`, a CloudKit-safe default) and changeable in the edit sheet. The viewfinder dims the area that gets cropped. The library, detail view, print animation, exports, video composite, print sheet and widget all respect the format.

### Sound design
A soft shutter/print "whirr" and a development-complete chime. There are no audio assets in the bundle yet. Add short `.caf` files and play them with `AVAudioPlayer`, respecting the silent switch (`.ambient` category while not recording).

### Watermark as marketing
Free exports carry the "Poly" watermark. Two options:
- Restyle it as "shot on poly." for recognisability.
- For free users only, add the App Store URL as an extra share item so Messages and Notes carry a link. Test whether it annoys people first.

---

## Already shipped (non-pricing work on this branch)

**Paid users**
- Premium exports are clean by default. The Settings toggle is now an opt-in "Show app logo on exports"; before, buyers kept the watermark until they found a toggle.
- "Welcome to Premium" screen after purchase or restore.
- Settings shows the active plan and its renewal/end date, plus "Manage Subscription" and "Upgrade to Lifetime" (for subscribers).
- Purchase state refreshes on every return to the foreground and on every `Transaction.updates` event, so expirations and refunds are picked up.
- New Premium perks: retro **date stamp** (photos and video exports) and **A4 print sheets** (3×3, cut marks, PDF).
- "Default Filter" setting now works (it was never read before) and only lists stocks the user owns.

**Conversion**
- Try before you buy: locked stocks can be previewed in the viewfinder with a "Previewing X · Unlock" banner. The shutter opens a paywall showing that filter applied to the user's own last photo.
- One free stock (SOLVA) and one free frame colour (SOLVA), marked FREE.
- Contextual paywall: the feature that triggered it is highlighted and the headline adapts. The feature grid is compact and the CTA stays pinned.
- One-time "You're on a roll" paywall after the 3rd capture (free users only).
- Onboarding shortened from 8 screens to 4 (welcome → film showcase → camera → paywall). Microphone access is requested on the first switch to Video; location through a soft card after the first photo.
- Copy updated from "5" to "10 film stocks" in the app and in `app_store_content.md`.
- Analytics funnel events (see above).

**Second batch (trial, formats, widget)**
- Free-trial-ready paywall with per-month price anchoring and a charge disclosure under the button (sections 1–2).
- Frame formats: Square, Wide and Mini (Premium).
- Memories home-screen widget (Premium) that opens the polaroid when tapped.

**Everyone**
- "Share as Story" (1080×1920) from the library context menu, and by long-pressing Share in the detail view.
- Review prompt moved from "7th shutter press" to positive moments (a finished print, a completed share, a save), once per version.
- Success haptic when a polaroid finishes developing.
- NEW badges on the Weird Film pack and a dot on the FILM button until the pack is seen (bump `FilmDrops.latestDropID` for the next drop).
- Frame colour can be picked before shooting (Filters sheet → Frame). Custom colours in the edit sheet are Premium, matching the marketing copy; they were previously free by accident.
- Library filter menu now lists all 10 stocks (it only had the classic 5).
