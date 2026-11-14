# Poly 1.0.9 — App Store release kit

Prepared Nov 13, 2026 from what the `improvements-1.0.9` branch actually shipped (see `PROMPTS/stats-and-app-improvement-plan.md`). Nothing here is live: Giuseppe applies it in App Store Connect.

Check limits after any edit:
```bash
python3 app-store/check_lengths.py app-store/1.0.9
```
```bash
python3 app-store/check_lengths.py app-store/1.0.9/search-a
```
```bash
python3 app-store/check_lengths.py app-store/1.0.9/search-b
```

- **Version:** `MARKETING_VERSION` 1.0.9 for the app and the widget (set Nov 14, 2026). Builds come from Xcode Cloud after a push to `main`.
- **Go-live date:** _not live yet_
- **Search option applied:** _not chosen yet_ (write A or B and the date here)

## What changes in the listing

| Field | Change | Files |
|---|---|---|
| Description | Opens with the assistant-friendly paragraph from `../1.0.7/ppo-test.md`, then a short list of facts (what's free, euro prices, 7-day trial, no account, iCloud, languages). 13 → **17 film stocks**, with the new looks named. New sections for importing photos and the camera controls. The separate privacy section is folded into the facts to stay under 4,000 characters. | `<lang>.md` |
| Promotional Text | Leads with the four new stocks, importing photos and tap to focus. Trial and no-trial variants, as before. | `<lang>.md` |
| What's New | 1.0.9 notes, also in `whats-new/`. | `<lang>.md`, `whats-new/` |
| Screenshot captions (ByJo) | Slide 3 says 17 film stocks. Re-export slide 3 from Figma; ideally recapture it with one of the new stocks on screen. | `<lang>.md` |
| Subtitle + Keywords | Two options per language, not chosen: see below. | `search-a/`, `search-b/` |
| App Name, In-App Purchases | Unchanged from 1.0.7. | `../1.0.7/` |

**Prices in the description** are the euro-area prices from `pricing-and-monetization.md` (€2.99 / €19.99 / €29.99). Check them in App Store Connect → Pricing before pasting; other storefronts are described as "local price in the app".

**Website:** it also says "13 film stocks". Change it to 17 when 1.0.9 is live, and add the four new looks.

## Search terms: pick one option (C2)

Search shows Poly a lot and almost nobody taps (0.2% of search impressions became downloads), so the subtitle and keywords are the suspect. Both options avoid trademarks and pass the length checker.

- **Option A — what people type** (`search-a/`): a new subtitle with vintage / retro / photo / filters, and keywords spent on what people pair with "camera" and "filter" (disposable, 90s, aesthetic, light leak…). Bigger change, bigger possible effect.
- **Option B — current positioning** (`search-b/`): subtitle unchanged; only the three weakest keywords (timelapse, widget, print and their translations) are swapped for search words.

How to measure: apply one with the 1.0.9 submission, write the go-live date above, then compare **search tap-through = search page views ÷ search impressions** (App Store Connect → App Analytics → Sources → App Store Search) for the four weeks before and the four weeks after.

- **Baseline, Aug 14 – Nov 11, 2026:** 186 ÷ 29,695 = **0.63%**. This includes the Oct 14–18 spike (12K impressions), which inflates impressions; for a cleaner baseline, read the four weeks before go-live from App Store Connect on the day you apply it.

## App Store accessibility declarations

The 1.0.9 accessibility pass (commit "accessibility pass…") was built for these. Enter in App Store Connect → App Accessibility only after the device walk-through below confirms each one:

| Declaration | Status after 1.0.9 |
|---|---|
| VoiceOver | Likely yes: every screen has labels, the library prints and gestures have actions. Needs a full VoiceOver pass on device. |
| Voice Control | Likely yes: custom controls are now buttons with names. Check the camera and library by voice on device. |
| Larger Text | Partly: settings, library, paywall, onboarding and What's New scale; the camera's small chip labels use the large content viewer instead. Decide after checking the largest sizes. |
| Dark Interface | Yes: the camera, paywall and onboarding are dark, and the library and settings follow the system. |
| Differentiate Without Color Alone | Yes: selected stocks, frames and formats also show a checkmark. |
| Sufficient Contrast | Likely yes: dim text was raised to at least 4.5:1, and Increase Contrast raises it further. |
| Reduced Motion | Yes: the print fades instead of sliding, the grain stops, springy transitions are off. |

The Xcode Accessibility Inspector audit wasn't run: the simulator hung at launch (see "Before submitting").

## Before submitting

The simulator on the Mac used for this work hangs at launch in `TrialReminder.sync` (a synchronous notification call on the main thread), so nothing below was checked in the app. Every item needs a real iPhone, Release build:

- [ ] Capture: the shutter is quicker (zero shutter lag / responsive capture), prints arrive in shooting order, a second press while a photo develops is ignored, flash off/auto/on works, the torch turns off when leaving Video.
- [ ] Tap to focus shows the square and refocuses; pinch to zoom is smooth, clamped, and locked while recording, in a time lapse and while holding a first exposure; the zoom chip follows.
- [ ] Volume buttons and Camera Control take a photo / start and stop a video; they don't fire while a sheet, the library or the print is up.
- [ ] Double exposure: the blend still matches the 1.0.8 look.
- [ ] Time lapse "save as video" for 10+ minutes: memory stays flat (Xcode memory gauge), the video plays and has the film look.
- [ ] Library with a few hundred prints scrolls smoothly; thumbnails appear without blank flashes after the first launch; month headers stick; favourites, kind filter and Undo work; the widget still updates.
- [ ] Import from Photos: a HEIC, a panorama and a 48 MP photo import, keep their date and place, locked stocks ask to unlock.
- [ ] Shared and saved prints are 2,400 px wide and the watermark, caption and date stamp look right; saving 20 at once doesn't run out of memory.
- [ ] New stocks render under a second on the oldest supported phone (the Debug build logs "Developed … in …" for each capture; `-FilmStockSnapshots YES` writes 12 MP timings to `Documents/FilmStockSnapshots/timings.txt`).
- [ ] VoiceOver, Voice Control, largest text size, Reduce Motion and Increase Contrast walk-through on every screen, then the declarations above.
- [ ] Confirm the names and swatches of GLÖD, FÖRN, TINN and PRIKK; if any changes, update `FiltersView.swift`, the What's New strings in the app and these files.

## Notes for the next stats check (C4)

- **US trials:** 2 US free trials were still running on Nov 11. When they end: did they convert? (The US had 37 downloads and $0 proceeds in 90 days.)
- **Retention message:** `../1.0.7/retention-offers.md` still says approval is pending. Record the approval date.
- **ChatGPT:** is App Referrer → ChatGPT still about half of first-time downloads (87 of 180 in Aug 14 – Nov 11)? The new description opening is aimed at it.
- **Search tap-through:** compare against the 0.63% baseline above once four weeks have passed since go-live.
