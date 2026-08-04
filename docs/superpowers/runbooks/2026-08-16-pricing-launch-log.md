# August 16, 2026 Pricing Launch Ledger

Launch window: Sunday, August 16, 2026 at 10:00 PT.

This non-secret ledger records immutable catalog identifiers and launch evidence.
Store exports in a dated, access-controlled folder outside Git; link their locations
below without including customer data or credentials in this repository.

## Catalog identifiers

| Platform | Term | Identifier | Price |
|---|---|---|---:|
| Stripe test — launch | weekly | prod_ItObh6ZCXtLU6g / price_1U0XpoALfCP0Km8wMYt14LcA | $19.99 / week |
| Stripe test — launch | monthly | prod_FOpVgsPA2MKMwi / price_1U0Xp3ALfCP0Km8wyJi3WT8h | $49.99 / month |
| Stripe test — launch | quarterly | prod_FOpWGIbC0VAykP / price_1U0XoNALfCP0Km8wzqeTPSq6 | $99.99 / 3 months |
| Stripe test — launch | annual | prod_FOpXrTwmi48Akh / price_1U0XnPALfCP0Km8wcWJJxXfI | $199.99 / year |
| Stripe live — launch | weekly | prod_IuxpOWAtc5jSQW / price_1U0ScJALfCP0Km8wqkBmml4l | $19.99 / week |
| Stripe live — launch | monthly | prod_Fm9cdQghZ4e5uU / price_1U0SbmALfCP0Km8wU1C1KqbQ | $49.99 / month |
| Stripe live — launch | quarterly | prod_Fm9cJuEYDNzMTK / price_1U0SbLALfCP0Km8wNYXazwDm | $99.99 / 3 months |
| Stripe live — launch | annual | prod_Fm9cBmk96oLT3p / price_1U0SaRALfCP0Km8wJncxSozk | $199.99 / year |
| Stripe live — legacy | weekly | prod_IuxpOWAtc5jSQW / price_1IJ7u3ALfCP0Km8w3HOUNuZd | $17.99 / week |
| Stripe live — legacy | monthly | prod_Fm9cdQghZ4e5uU / price_1QyfQpALfCP0Km8wK0rdygqU | $39.99 / month |
| Stripe live — legacy | quarterly | prod_Fm9cJuEYDNzMTK / price_1IJQvPALfCP0Km8wi13vhjWJ | $66.99 / 3 months |
| Stripe live — legacy | annual | prod_Fm9cBmk96oLT3p / price_1IJQx5ALfCP0Km8wgcljJydj | $149.99 / year |
| Apple | annual | com.Modamily.Modamily.twelveMonthsAutoSubscriptionNew | $149.99 US |
| Apple | quarterly | com.Modamily.Modamily.threeMonthsAutoSubscriptionNew | $66.99 US |
| Apple | monthly | com.Modamily.Modamily.oneMonthAutoSubscriptionNew | $39.99 US |
| Apple | weekly | com.Modamily.Modamily.oneWeekAutoSubscriptionNew | $17.99 US |
| Google | annual | sub_12m / p1y | $149.99 US |
| Google | quarterly | sub_3m / p3m | $64.99 US |
| Google | monthly | sub_1m / p1m | $39.99 US |
| Google | weekly | sub_1w / p1w | $17.99 US |

## Execution record

| Gate | Status | UTC timestamp | PT timestamp | Evidence |
|---|---|---|---|---|
| Stripe test Price creation | COMPLETE — four exact recurring USD Prices created on existing test Products with required metadata | 2026-08-04T02:12:27Z | 2026-08-03 19:12:27 PDT | Dashboard detail pages verified exact amount/interval, zero active subscriptions, `pricing_launch=2026-08-16`, and term-specific `plan_type`; IDs recorded above |
| Stripe live Price creation | COMPLETE — four pre-existing exact Prices retained and required metadata added | 2026-08-04T02:12:27Z | 2026-08-03 19:12:27 PDT | Dashboard detail pages verified exact amount/interval, zero active subscriptions, `pricing_launch=2026-08-16`, and term-specific `plan_type`; no duplicate live Prices created |
| Stripe test Checkout verification | BLOCKED — catalog/config and mocked route/webhook checks pass; hosted application flow unavailable | 2026-08-04T02:15:53Z | 2026-08-03 19:15:53 PDT | No local/staging app server, test Stripe credential, or safe authenticated test user was available. No production checkout or real payment was attempted. See Task 6 report for exact unrun subchecks |
| Apple schedule confirmed | NOT EXECUTED | — | — | — |
| Google production prices saved | NOT EXECUTED | — | — | — |
| Apple catalog visibly live | NOT EXECUTED | — | — | — |
| Google catalog visibly live | NOT EXECUTED | — | — | — |
| Stripe/web deploy complete | NOT EXECUTED | — | — | — |

## Baseline exports

| Artifact | Required contents | Status | Access-controlled external location | Evidence |
|---|---|---|---|---|
| Stripe active subscriptions export | Subscription ID, Price ID, amount, currency, status, current-period end, and customer country when available | NOT EXECUTED — owner created four live Prices, not this export | — | 2026-08-03 owner clarification; no customer data was exported during the read-only catalog inventory |
| App Store Connect current and future subscription-price CSV exports | All four product IDs | COMPLETE — verified current and upcoming CSV ZIP exports for all terms | `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-annual-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-annual-upcoming-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-quarterly-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-quarterly-upcoming-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-monthly-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-monthly-upcoming-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-weekly-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-weekly-upcoming-prices-2026-08-03.zip` | 2026-08-03 |
| Google Play base-plan regional-price export/screenshots | All four base plans and current legacy-price-point view | COMPLETE — visually validated loaded regional country/price tables and actual loaded legacy-price-point tables for p1y, p3m, p1m, and p1w | `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-annual-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-annual-legacy-price-points-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-quarterly-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-quarterly-legacy-price-points-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-monthly-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-monthly-legacy-price-points-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-weekly-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-weekly-legacy-price-points-2026-08-03.png` | 2026-08-03 |
| Active-at-date subscriber counts by platform | Point-in-time counts; do not use a six-month Google total as an active count | PARTIAL — Stripe 115 owner-provided; Apple Active Plans 68 as of 2026-08-02; Google active-at-date UNAVAILABLE | `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-active-plans-asof-2026-08-02.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-statistics-{metric-selector,monetization-metrics}-2026-08-03.png` | 2026-08-03; Google Statistics exposes no active subscription/subscriber metric |
