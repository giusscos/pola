# Poly — Product Page Optimization test: skipped

**Decision (Nov 6, 2026):** no test. Poly's traffic is too small for App Store Connect to reach a confident result within its 90-day limit. Nothing was created in App Store Connect, and no listing change went live.

## What was planned

1. **Screenshots, current vs. the ByJo-style set B** (the Oct 29 plan). Dropped because on Nov 6 the live US product page was already showing set B: "Instant film", "Double exposure" and "13 film stocks", with orange titles on grey. It has been live since 1.0.6 (Sep 28), so the test would have compared the listing with itself.
2. **App icon, orange vs. SKIFT pink**, 50/50, all 5 languages. Possible without a new build, because 1.0.7 ships the 7 alternate icons (`ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES`). Dropped after reading Apple's duration estimate below.

## Why: App Store Connect's own estimate

From the Create Test dialog on Nov 6, 2026: 1 treatment at 50%, 90% confidence. It's based on the week before: 1,115 impressions and a 0.9% conversion rate, which is about 10 downloads a week.

| Improvement to detect | Impressions needed | Estimated duration |
|---|---|---|
| +10% | — | 726 weeks |
| +25% | 117,552 | 105 weeks |
| +50% | 28,830 | 26 weeks |
| +100% | 7,805 | 7 weeks |

Apple ends every test after 90 days, about 13 weeks. Only a change that roughly doubles conversion could show up in time, and neither a color swap nor a screenshot style is likely to do that. Running it anyway would have frozen the name, subtitle, keywords and screenshots for up to 13 weeks, almost certainly for a "needs more data" result.

## When to reconsider

When a test could detect +50% in about 4 weeks. That needs about 1,000 impressions a day at the same conversion rate, or a higher conversion rate. Check the estimate again in the Create Test dialog: fill in the form, expand "Estimate Your Test Duration", then cancel. Nothing is created until you click Create Test.

If the icon test happens later, this was its setup:

| Field | Value |
|---|---|
| Reference name | `Icon: orange vs SKIFT pink` |
| Number of treatments | 1 |
| Traffic proportion | 50% |
| Localizations | All 5, the default |
| Treatment A | App Icon tab → Change → `AppIcon-Skift`. Screenshots untouched; the treatment then uses the original's. |

Things to remember for it:
- People who download from the treatment get the treatment icon on their Home Screen.
- If it wins, make it the primary icon in the next app version yourself. Apple doesn't apply an icon from a test.
- Every build released during the test must keep all the alternate icons.

## What to do instead

- **Make one listing change at a time and judge it before and after on search tap-through** (search page views ÷ search impressions). Tap-through has more events than downloads, so it gives an answer sooner. Write each go-live date in this folder's `README.md`.
- **Pick the next change at the Nov 7–10 stats check**, after reading Oct 19 – Nov 6 without the Oct 14–18 US spike.
- **Work that doesn't need a test:**
  - the website refresh (poly-vintage.com, in `~/Developer/polyWeb`)
  - an earlier review prompt (the US page shows 3 ratings)
  - the paywall: 1 trial from 37 downloads, Oct 15–28.

## Proposed description opening for ChatGPT

ChatGPT sent 21 of 37 downloads from Oct 15 to 28. It reads the App Store description, so the first lines should say plainly what Poly is and who it's for. Proposed new opening paragraph (en-US), replacing "Poly turns your iPhone into an instant film camera.":

```
Poly is an instant film camera app for iPhone. Every photo slides out as a print and develops in your hands, with 13 film stocks, 3 vintage lenses and Classic, Square, Wide and Mini formats. It's for anyone who loves the look of instant film without buying film packs. Free to use; Premium unlocks every look.
```

The description needs a new app version, and it counts as a listing change. Decide at the Nov 7–10 check whether it's the next one. Translate it into all 5 languages and keep it in line with the website copy.
