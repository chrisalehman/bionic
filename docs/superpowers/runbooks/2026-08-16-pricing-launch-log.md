# August 16, 2026 Pricing Launch Ledger

Launch window: Sunday, August 16, 2026 at 10:00 PT.

This non-secret ledger records immutable catalog identifiers and launch evidence.
Store exports in a dated, access-controlled folder outside Git; link their locations
below without including customer data or credentials in this repository.

## Catalog identifiers

| Platform | Term | Identifier | Legacy price |
|---|---|---|---:|
| Stripe live | weekly | price_1IJ7u3ALfCP0Km8w3HOUNuZd | $17.99 |
| Stripe live | monthly | price_1QyfQpALfCP0Km8wK0rdygqU | $39.99 |
| Stripe live | quarterly | price_1IJQvPALfCP0Km8wi13vhjWJ | $66.99 |
| Stripe live | annual | price_1IJQx5ALfCP0Km8wgcljJydj | $149.99 |
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
| Stripe test Price creation | NOT EXECUTED | — | — | — |
| Stripe live Price creation | NOT EXECUTED | — | — | — |
| Apple schedule confirmed | NOT EXECUTED | — | — | — |
| Google production prices saved | NOT EXECUTED | — | — | — |
| Apple catalog visibly live | NOT EXECUTED | — | — | — |
| Google catalog visibly live | NOT EXECUTED | — | — | — |
| Stripe/web deploy complete | NOT EXECUTED | — | — | — |

## Baseline exports

| Artifact | Required contents | Status | Access-controlled external location | Evidence |
|---|---|---|---|---|
| Stripe active subscriptions export | Subscription ID, Price ID, amount, currency, status, current-period end, and customer country when available | OWNER COMPLETED — PATH NOT RECORDED | Owner-provided; do not copy customer data into Git | 2026-08-03 owner confirmation |
| App Store Connect current and future subscription-price CSV exports | All four product IDs | COMPLETE — verified current and upcoming CSV ZIP exports for all terms | `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-annual-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-annual-upcoming-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-quarterly-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-quarterly-upcoming-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-monthly-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-monthly-upcoming-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-weekly-current-prices-2026-08-03.zip`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-weekly-upcoming-prices-2026-08-03.zip` | 2026-08-03 |
| Google Play base-plan regional-price export/screenshots | All four base plans and current legacy-price-point view | COMPLETE — visually validated loaded regional country/price tables and actual loaded legacy-price-point tables for p1y, p3m, p1m, and p1w | `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-annual-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-annual-legacy-price-points-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-quarterly-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-quarterly-legacy-price-points-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-monthly-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-monthly-legacy-price-points-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-weekly-regional-price-table-2026-08-03.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-weekly-legacy-price-points-2026-08-03.png` | 2026-08-03 |
| Active-at-date subscriber counts by platform | Point-in-time counts; do not use a six-month Google total as an active count | PARTIAL — Stripe 115 owner-provided; Apple Active Plans 68 as of 2026-08-02; Google active-at-date UNAVAILABLE | `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/apple-active-plans-asof-2026-08-02.png`; `/Users/ivanfatovic/Claude-Work/Outputs/pricing-launch-2026-08-16-private/google-statistics-{metric-selector,monetization-metrics}-2026-08-03.png` | 2026-08-03; Google Statistics exposes no active subscription/subscriber metric |
