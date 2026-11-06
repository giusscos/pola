# Poly 1.0.7 — App Store release kit

Everything App Store Connect needs for 1.0.7, in English (`en.md`), German (`de.md`), Spanish (`es.md`), French (`fr.md`) and Italian (`it.md`). The files follow the 1.0.6 kit; see `../1.0.6/README.md` for the background on the name, subtitle, keywords and the screenshot set.

Check limits after any edit:
```bash
python3 app-store/check_lengths.py app-store/1.0.7
```

## What changed vs. 1.0.6

| Field | Change |
|---|---|
| Promotional Text | Leads with Double Exposure, iPhone Duo and the app icons. |
| Description | New DOUBLE EXPOSURE and MADE FOR IPHONE DUO sections before SHARE & PRINT; Premium now lists double exposure and colorful app icons. |
| What's New | 1.0.7 notes (also in `whats-new/`). |
| Screenshot captions (ByJo style) | Double exposure is slide 2; the 1.0.6 slides 2–5 move to 3–6. |
| Screenshot captions (iPhone Duo) | New 5-slide set for the iPhone Duo inner display. |

App Name, Subtitle, Keywords and In-App Purchases are unchanged.

## Screenshots

Both sets live on the Poly page in Figma, next to the 1.0.6 sections. As in 1.0.6, the English sections hold the master components and the other languages are linked instances with only the text changed. Frame names export into their own folder (`1.0.7/B/<lang>/`, `1.0.7/Duo/<lang>/`), so they don't overwrite the 1.0.6 exports.

### iPhone: "App Store 1.0.7 · B (ByJo style)"

The 1.0.6 ByJo set (6.5" iPhone, 1242 × 2688) with Double exposure added as slide 2, inside the first three that show in search results:

1. Instant film · 2. **Double exposure** (2/2 step with the ghost and blend slider) · 3. Film stocks · 4. Formats · 5. Watch it develop · 6. Write on it

### iPhone Duo: "App Store 1.0.7 · iPhone Duo (inner)"

Inner display, landscape **2853 × 2007**, same look as the ByJo set (`#EBEBEB`, orange title, device running off the bottom) with the Star White Duo mockups:

1. **Instant film:** open, camera (`open-02-camera`)
2. **Double exposure:** open, 2/2 step (`open-01-double-2of2`)
3. **Every control:** half-folded, 1/2 step with the format, color and film rows (`half-01-double-1of2`)
4. **Your prints:** open, 4-column library (`open-03-library`)
5. **Folded too:** closed Duo, 2/2 step (`closed-03-double-2of2`)

The captures are in `captures/` (not committed). App Store Connect's iPhone Duo outer-display set (1398 × 2034) isn't built yet; the closed captures are that size if you want one.

## Product Page Optimization test

**Skipped (Nov 6, 2026).** App Store Connect estimated 26 weeks to detect a +50% change at Poly's traffic, and tests stop after 90 days. No test was created and no listing change went live. Reasons, the icon-test setup for later, and what to do instead: `ppo-test.md`.
