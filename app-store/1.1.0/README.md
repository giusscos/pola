# poly. 1.1.0 — App Store release kit

Everything App Store Connect needs for 1.1.0, in English (`en.md`), German (`de.md`), Spanish (`es.md`), French (`fr.md`) and Italian (`it.md`). Each file has: App Name, Subtitle, Promotional Text, Description, Keywords, What's New, screenshot captions and In-App Purchase metadata.

Check limits after any edit:
```bash
python3 app-store/check_lengths.py app-store/1.1.0
```

The build is already set to **1.1.0** (`MARKETING_VERSION` for the app and the widget).

---

## What changed vs. the 1.0.x listing (`app_store_content.md`)

| Field | 1.0.x | 1.1.0 | Why |
|---|---|---|---|
| App Name | `poly.` | `poly. – Instant Film Camera` (localized) | The name is the strongest search signal; `poly.` alone ranks for nothing. The Home Screen name stays **Poly**. |
| Subtitle | `Authentic Polaroid Camera` | `Retro film looks that develop` | "Polaroid" is a registered trademark. Using it in metadata can get the update rejected (App Review 2.3.7 / 5.2.1). |
| Keywords | included `polaroid`, repeated words from the name | no trademarks; no words already in name/subtitle | Apple indexes name and subtitle words already, so repeating them wastes bytes. |
| Description | 5 film stocks, "watermark-free" | 10 stocks, formats, widget, date stamp, print sheets, Stories, privacy, full subscription terms | Matches what the app does now. Includes the auto-renew wording App Review expects. |
| "Ektar" (Kodak) | in onboarding copy | "golden tones" | Also a third-party trademark; fixed in the app too. |

> **Still worth deciding:** the app UI uses "polaroid" as a common noun ("your polaroids"). That's lower risk than metadata, but if you ever get a trademark complaint, "print" or "instant" are drop-in replacements. Store metadata for 1.1.0 is already clean.

---

## Screenshots

Required size: **6.9" iPhone** (1320 × 2868, or 1290 × 2796). App Store Connect scales it down for smaller iPhones. The app is iPhone-only, so no iPad set is needed.
Upload the same order in every language. Only the caption text changes (from each language file).

| # | Caption theme | What to capture | Tips |
|---|---|---|---|
| 1 | Instant film on iPhone | The **print animation**: polaroid mid-development over the camera | Take it about 5 s after the shutter so the image is half developed. Use the SOLVA stock. |
| 2 | 10 film stocks | **Filters sheet** at the large detent | Scroll so Classic Film and Weird Film (with NEW badges) are both visible. Premium account, so there are no locks. |
| 3 | See it before you shoot | **Camera** with a Weird Film stock selected and the "Previewing …" banner | Use a free account for this one so the banner shows. A bright outdoor scene reads best. |
| 4 | Classic, Square, Wide, Mini | **Library** in 2 columns with one polaroid of each format and a few frame colors | Seed shots in each format. Mix white, SOLVA and VYLUR frames. |
| 5 | Relive this day | **Home Screen** with the medium Memories widget ("1 YEAR AGO TODAY") | Needs a photo dated exactly one year ago; the simulator is easiest. |
| 6 | Write on it. Flip it. | **Detail view**: one screenshot of the front with a caption and date stamp, one of the back with the map, composed side by side | Handwriting font, a real-looking caption such as "sunday market". |
| 7 | Made for Stories | The **Story export** (9:16 image) shown inside a phone frame, or the share sheet over it | The rendered story image looks great as the hero of this slide. |
| 8 | Prints that move | **Video polaroid** in the detail view, or a time lapse stack in the library | Add a small ▶ badge in the overlay design to show that it moves. |

**Layout suggestion:** headline at the top (bold, expanded width, like the paywall title), subline under it at 60% opacity. Use the dark app background (`#0F0F1A`) with the warm gold accent (`#FFCC4D`) for keywords. Keep captions to 2 lines; the checker limits headlines to 31 and sublines to 45 characters.

**App Preview video (optional, big conversion lift for camera apps):** 15–20 s showing shutter → print → shake to develop → flip to map → share as Story. No captions needed.

---

## App Store Connect checklist

- [ ] New version **1.1.0**; paste each field from the language files (5 localizations).
- [ ] Upload screenshots (8 per language, same order).
- [ ] **Promotional Text:** use the "trial live" version only once the free trial is approved. You can change this field anytime without review.
- [ ] **Subscriptions:**
  - Update display names and descriptions (IAP table in each file) for Monthly, Yearly and Lifetime, in 5 languages.
  - Add the **1-week free introductory offer** to Yearly, if you're launching the trial.
  - Subscription group display name: `poly. Premium`.
- [ ] **App Privacy:** unchanged. There's no analytics SDK, and location plus photos stay on device and in the user's iCloud. Confirm "Data Not Collected" is still accurate for your answers.
- [ ] **Age rating:** unchanged.
- [ ] **App Review notes** (paste into "Notes"):
  ```
  No login required. Premium features (film stocks, frame formats, date stamp,
  Memories widget, print sheets) can be tested with a sandbox account.
  The Memories widget: add it from the Home Screen (Edit > Add Widget > Poly);
  it shows a locked state until Premium is active. Location is optional and is
  only requested after the first photo, from an in-app card.
  ```
- [ ] Make sure the App Group `group.com.giusscos.pola` and the widget bundle ID are registered (open the project in Xcode once, signed in, with automatic signing).
- [ ] After release: update `whats-new/` for the next version.
