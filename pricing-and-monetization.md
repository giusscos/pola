# poly. — Pricing & Monetization Backlog

Parked on purpose: everything here changes **what people pay** or needs App Store Connect / Xcode work outside the code. The conversion and UX work that didn't touch prices shipped on the `claude/conversion-ux-improvements-06632c` branch (see "Already shipped" at the bottom).

Current catalogue (`pola/offlineStore.storekit`):

| Product | ID | Price | Notes |
|---|---|---|---|
| Monthly | `com.pola.premium.monthly` | €2.99 | auto-renewable, group "Premium" |
| Yearly | `com.pola.premium.yearly` | €19.99 | auto-renewable, pre-selected on paywall |
| Lifetime | `com.pola.premium.lifetime` | €29.99 | non-consumable |

---

## 1. Free trial on Yearly (highest expected impact)

**What:** 7-day free trial as an *introductory offer* on the yearly plan. Monthly stays trial-less so the trial nudges people to yearly.

**Why:** Photo/camera apps usually convert best with a trial. Right now nobody can try Premium before paying. The in-app "preview a locked filter" flow helps, but it isn't a real trial.

**How:**
1. App Store Connect → Subscriptions → Yearly → Introductory Offers → Free, 1 week, all territories.
2. Mirror it in `offlineStore.storekit` / `onlineStore.storekit` (`introductoryOffer` on the yearly product) so it can be tested locally.
3. `PaywallView`:
   - Check eligibility with `await product.subscription?.isEligibleForIntroOffer`.
   - If eligible and yearly is selected, change the CTA to **"Try 7 days free"** and add a line under it: *"then €19.99/year. Cancel anytime."* Guideline 3.1.2 requires the price after the trial to be clearly visible.
   - Add a trial badge on the yearly card.
4. Add a `trialStarted` analytics event (`Transaction.offer?.type == .introductory`).
5. Optional: a local notification 2 days before the trial ends ("Your trial ends Thursday"). Apple doesn't require it, but it reduces refunds and 1★ reviews.

## 2. Price anchoring on the paywall

**What:** Show the yearly price per month and the saving compared with monthly.

- Yearly card subtitle: **"€1.67/mo · save 44%"**, computed from `product.price / 12` against the monthly `product.price`. Never hardcode it, because prices vary by storefront.
- Use `product.priceFormatStyle` so the currency is formatted correctly.
- Optional: show the monthly-equivalent crossed out (€35.88 → €19.99).

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

## 6. Paywall experiments to run once analytics is live

| Experiment | Variants | Metric |
|---|---|---|
| Milestone paywall timing | after 3rd vs 5th photo | trial/purchase rate per install |
| Onboarding paywall | hard (no "Continue for Free" for 3 s) vs current | install → paid, D7 retention |
| Free filter | SOLVA vs FLÄRN vs none | install → paid |
| Plan order | Yearly first vs Monthly first | yearly share of purchases |

The free filter and free frame are one flag each (`isFree:` in `FiltersView.swift`), so this experiment is cheap to set up.

---

## Non-pricing items deferred (need Xcode / accounts / design)

### Analytics backend
`pola/Managers/Analytics.swift` is live and already tracks the whole funnel (paywall shown per context, purchase started / completed / cancelled, locked-filter previews, captures, shares, story and print exports, review prompts, location opt-in). For now events only go to the unified log (`log stream --predicate 'subsystem == "com.pola"'`).
To ship: add **TelemetryDeck** (privacy-friendly, no ATT prompt) via SPM, then append a sink:
```swift
struct TelemetryDeckSink: AnalyticsSink {
    func send(_ event: AnalyticsEvent, parameters: [String: String]) {
        TelemetryDeck.signal(event.rawValue, parameters: parameters)
    }
}
// in polaApp.init(): Analytics.sinks.append(TelemetryDeckSink())
```
Update the privacy policy and the App Store privacy label when you do.

### Home-screen widget ("On this day" / random memory)
A strong reason for people to come back, and a natural Premium perk. Needs:
1. A Widget Extension target (Xcode → File → New → Target → Widget Extension).
2. An App Group (e.g. `group.com.giusscos.pola`) on both targets, registered in the developer portal.
3. Move the SwiftData store into the App Group container (`ModelConfiguration(groupContainer: .identifier(...))`), with a one-time migration of the existing store.
4. A timeline provider that picks one photo per day, with a small polaroid-style SwiftUI view.

### Frame formats (SX-70 square, Wide, Mini)
The 3:4 frame is hardcoded in several places: `PolaroidPhotoCell`, `compositePolaroidVideo` (270×360), `PolaroidPrintAnimationVC`, the library layout (`0.75` aspect) and the detail view. Adding formats means:
1. Add `frameFormat` to `PolaroidEntry` (a CloudKit-safe default).
2. Replace each hardcoded aspect ratio with a lookup from the format.
3. Add a picker in the Filters sheet, next to "Frame".

This is a good follow-up Premium drop.

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

**Everyone**
- "Share as Story" (1080×1920) from the library context menu, and by long-pressing Share in the detail view.
- Review prompt moved from "7th shutter press" to positive moments (a finished print, a completed share, a save), once per version.
- Success haptic when a polaroid finishes developing.
- NEW badges on the Weird Film pack and a dot on the FILM button until the pack is seen (bump `FilmDrops.latestDropID` for the next drop).
- Frame colour can be picked before shooting (Filters sheet → Frame). Custom colours in the edit sheet are Premium, matching the marketing copy; they were previously free by accident.
- Library filter menu now lists all 10 stocks (it only had the classic 5).
