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
| Stripe active subscriptions export | Subscription ID, Price ID, amount, currency, status, current-period end, and customer country when available | NOT EXECUTED | NOT EXECUTED | — |
| App Store Connect current and future subscription-price CSV exports | All four product IDs | NOT EXECUTED | NOT EXECUTED | — |
| Google Play base-plan regional-price export/screenshots | All four base plans and current legacy-price-point view | NOT EXECUTED | NOT EXECUTED | — |
| Active-at-date subscriber counts by platform | Point-in-time counts; do not use a six-month Google total as an active count | NOT EXECUTED | NOT EXECUTED | — |
