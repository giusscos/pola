# Poly — cancellation offer and win-back offers

**Status (Nov 6, 2026):** all created in App Store Connect.
- **Win-back offers:** start Nov 7, 2026, with no end date.
- **Retention message and its two offers:** submitted to App Review on Nov 6, status "Waiting for Review" (Apple says up to 48 hours). Write the approval date here once it's approved:
  - Retention message approved: _pending_

None of this needs an app update or a server. Poly doesn't intercept StoreKit messages, so Apple's sheets show on their own. Purchases from them arrive through the existing `Transaction.updates` listener in `PremiumManager`.

| | When people see it | Who gets the discount |
|---|---|---|
| **Retention message + offer** | The moment they tap Cancel Subscription | Subscribers with at least 1 month of paid subscription. Trial users see the message but no offer. |
| **Win-back offer** | After the subscription has ended: in Manage Subscriptions, and inside Poly on iOS 18+ | Former subscribers with at least 1 paid month, 1–24 months after it ended, for their most recently ended plan |

Expect small numbers: 2 cancellations and $3 in proceeds from Oct 15 to 28, and most cancellations were probably trials, which don't qualify for either discount.

## 1. Retention message "Keep Premium"

- **App Store Connect:** Subscriptions → Retention Messaging → Keep Premium (`retention-messages/d860f2b5-77a1-4275-8276-aa6679dfc25a`)
- **Subscriptions:** Premium Monthly and Premium Yearly
- **Image:** none (optional; needs 3840 × 2160 or 5244 × 2950)
- **Limits:** header 66 characters, body 144. Apple rejects text that mentions prices or offers; it adds the offer itself.

| Language | Header | Body |
|---|---|---|
| en-US | Keep every film look | Premium keeps all 13 film stocks, vintage lenses, every format, double exposure and the Memories widget. Your prints stay in your library. |
| de | Behalte jeden Film-Look | Mit Premium behältst du alle 13 Filme, Vintage-Objektive, jedes Format, die Doppelbelichtung und das Erinnerungs-Widget. Deine Abzüge bleiben. |
| es-ES | Conserva cada película | Con Premium conservas 13 películas, objetivos vintage, todos los formatos, la doble exposición y el widget de recuerdos. Tus fotos se quedan. |
| fr | Gardez chaque pellicule | Avec Premium, gardez 13 pellicules, des objectifs vintage, tous les formats, la double exposition et le widget Souvenirs. Vos tirages restent. |
| it | Tieni ogni pellicola | Con Premium tieni le 13 pellicole, gli obiettivi vintage, tutti i formati, la doppia esposizione e il widget Ricordi. Le tue stampe restano. |

### Retention offers

| Field | Yearly | Monthly |
|---|---|---|
| Reference name | Retention Yearly 50% | Retention Monthly 50% |
| Offer identifier | `retention_yearly_50` | `retention_monthly_50` |
| Type | Pay up front, 1 year | Pay as you go, 3 months |
| US price | $9.99 (regular $19.99) | $1.49 a month (regular $2.99) |
| Euro price | €9.99 (regular €22.99) | €1.99 a month (regular €2.99) |
| Paid subscription duration | At least 1 month | At least 1 month |
| Wait between offers | None (the default) | None (the default) |
| Countries | All 175 | All 175 |

## 2. Win-back offers

| Field | Yearly | Monthly |
|---|---|---|
| Apple ID | 6831568489 | 6831569682 |
| Reference name | Win-back Yearly 50% | Win-back Monthly 50% |
| Offer identifier | `winback_yearly_50` | `winback_monthly_50` |
| Billing plan | 1 Year Upfront | Monthly |
| Dates | Nov 7, 2026 → no end date | Nov 7, 2026 → no end date |
| Priority | Normal | Normal |
| Minimum paid duration | 1 month | 1 month |
| Time since last subscribed | 1–24 months | 1–24 months |
| Wait between offers | 12 months | 6 months |
| Type | Pay up front, 1 year | Pay as you go, 3 months |
| US price | $9.99 | $1.49 a month |
| Euro price | €9.99 | €1.99 a month |
| Countries | All 175 | All 175 |
| Promoted on the App Store | No | No |
| Redemption URL | https://apps.apple.com/win-back/6831568489 | https://apps.apple.com/win-back/6831569682 |

Promotion stays off: promoting would put the offer on the product page, which counts as a listing change for the search tap-through comparison.

Reference names, identifiers and prices can't be changed. Offers can be deleted at any time.

## Gaps to know about

- **Euro discounts aren't 50%.** App Store Connect converted the US prices: Yearly is €9.99 against €22.99 (57% off), Monthly €1.99 against €2.99 (33% off). Prices can't be changed after creation; to fix them, delete an offer and create a new one.
- **"Monthly with a 12-Month Commitment" has no win-back offer.** Yearly also sells this billing plan, and only the 1 Year Upfront plan got one.
- **The retention offers have no wait between offers.** A subscriber could cancel at every renewal and get the discount again. At Poly's volume this doesn't matter yet.

## How to tell if it works

- **App Store Connect → Sales and Trends:** filter by offer, using the identifiers above.
- **Subscription events:** "Voluntary Churn" should fall if the retention offer saves anyone.
- With Poly's volume, read this over months, not weeks.
