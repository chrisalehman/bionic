# Modamily Global New-Subscriber Pricing Design

Date: 2026-08-03
Status: Approved design; implementation not started

## Decision

Launch a coordinated worldwide price increase for new subscribers on Stripe, Apple App Store, and Google Play. Preserve every existing subscriber on their current price. Keep the current products, billing intervals, paywall structure, and plan positioning.

The U.S. anchor prices are:

| Term | Current Stripe/Apple | Current Google | New anchor | Increase |
|---|---:|---:|---:|---:|
| Annual | $149.99 | $149.99 | $199.99 | 33.3% |
| Quarterly | $66.99 | $64.99 | $99.99 | 49.3%–53.9% |
| Monthly | $39.99 | $39.99 | $49.99 | 25.0% |
| Weekly | $17.99 | $17.99 | $19.99 | 11.1% |

Apple and Google will generate localized equivalents for their storefronts. Stripe will retain its existing currency behavior; if checkout currently charges USD globally, this change will continue charging USD globally. This project does not introduce a new currency-localization system.

## Goals

- Increase cash collected and normalized recurring revenue from newly acquired subscribers.
- Apply one consistent plan ladder across web, iOS, and Android.
- Protect retention and customer trust by grandfathering existing subscribers.
- Measure cash, normalized recurring revenue, conversion, and term mix separately.
- Make rollback possible without deleting legacy prices or migrating existing subscriptions.

## Non-goals

- Repricing or migrating existing subscribers.
- Changing subscription durations, entitlements, trials, or cancellation behavior.
- Redesigning the paywall or changing which plan is preselected.
- Running a price A/B test or geographic holdout in this launch.
- Changing win-back, introductory, or promotional offer amounts.
- Building a new multi-currency system for Stripe.
- Treating charge count as the primary success metric.

## Chosen rollout approach

Three approaches were considered:

1. **Coordinated global launch — chosen.** Configure all platforms for new subscribers, verify the store catalogs, then activate the web mapping. This maximizes speed and keeps the public ladder consistent.
2. **Platform-staged launch.** Launch Stripe first, then Google and Apple. This improves platform-level attribution but creates temporary price inconsistency and delays mobile upside.
3. **Price holdout.** Retain the old ladder for a control group. This offers the cleanest causal estimate but cannot be implemented consistently across all three platforms without additional experiment infrastructure.

The coordinated launch is the simplest approach that satisfies the approved worldwide scope. Platform-specific activation timestamps will still be recorded because app-store propagation is not instantaneous.

## Customer cohort rules

- A subscriber whose paid subscription or free trial starts before a platform's activation timestamp belongs to the legacy cohort.
- A subscriber whose subscription starts at or after that timestamp belongs to the new-price cohort.
- Legacy subscribers remain on their legacy price through renewals, plan pauses, grace periods, and ordinary billing retries where the platform supports preserved pricing.
- Canceling and later starting a new subscription creates a new-price subscription.
- Changing to a different term after launch uses the new price for the destination term.
- No process may bulk-migrate legacy subscribers to the new prices.

## Platform design

### Stripe and web checkout

- Create four new immutable Stripe Price objects for the approved U.S. amounts and existing billing intervals.
- Keep every existing Price object active until no legacy subscription depends on it. Do not overwrite or delete legacy prices.
- Update the server-side term-to-Price mapping used for newly created Checkout Sessions or subscriptions.
- Existing subscriptions retain their current Price IDs and renewal amounts.
- Update paywall display values and savings calculations so displayed prices exactly match checkout.
- Preserve the current plan order and positioning: annual first, quarterly preselected and labeled “Most Popular,” monthly, then weekly.
- Record the selected term, Price ID, checkout currency, country when available, and pricing cohort in analytics.

### Apple App Store

- Keep the existing four subscription product IDs and durations.
- Schedule the new U.S. anchors and Apple's automatically generated localized equivalents for every enabled storefront.
- Select preserved pricing for existing subscribers; do not choose the option that raises existing renewal prices.
- Verify that active free trials and introductory offers entered before activation remain in the legacy cohort under Apple's preservation rules.
- Do not alter the active win-back or introductory offers in this launch.
- Review the generated price matrix before activation, with explicit checks for the United States, United Kingdom, Canada, Australia, Germany, France, Italy, Spain, and the Netherlands.

### Google Play

- Keep the existing active base-plan IDs for annual, quarterly, monthly, and weekly subscriptions.
- Set the new U.S. anchors and Google's converted regional prices for every enabled country or region.
- Preserve existing subscribers as legacy price cohorts. Do not migrate those cohorts to the new base-plan prices.
- Do not change offer eligibility, free-trial phases, grace periods, account hold, or resubscribe behavior.
- Review the generated regional price matrix for the same priority markets used for Apple.

## Activation sequence

1. Record the legacy product and Price IDs, regional price matrices, active offers, and active-at-date subscriber counts. Do not substitute date-range period totals for active counts.
2. Create the four new Stripe Price objects without changing production checkout mappings.
3. Prepare Apple and Google regional prices and preservation settings.
4. Verify test accounts and current app builds fetch prices from the stores rather than relying on stale hard-coded amounts.
5. Activate or schedule the mobile-store changes. Record the actual visible-production timestamp for each store.
6. After both mobile catalogs expose the new prices, deploy the Stripe/web mapping and updated paywall copy.
7. Run new-subscriber purchase checks on web, iOS, and Android.
8. Run legacy-renewal checks or platform-supported renewal simulations to verify grandfathering.

This order may create a short mobile-before-web propagation window. That is preferable to showing a web price that mobile clients cannot yet retrieve. The launch log must record the window rather than claiming a perfectly simultaneous release.

## Validation and acceptance criteria

The launch is complete only when all of the following are true:

- A new U.S. customer sees and is charged $199.99 annual, $99.99 quarterly, $49.99 monthly, or $19.99 weekly on each applicable platform.
- Sample new customers in the priority non-U.S. storefronts see the approved localized equivalents and are charged the displayed currency and amount.
- Existing test subscriptions or renewal simulations remain at their legacy prices.
- Quarterly remains preselected and labeled “Most Popular,” and all savings copy is mathematically correct.
- Stripe events and mobile server notifications map the purchase to the correct term and pricing cohort.
- Entitlements activate exactly as they did before the change.
- Failed, canceled, or interrupted purchases do not grant entitlement.
- The analytics pipeline can distinguish platform, term, country when available, legacy/new cohort, cash collected, and normalized recurring revenue.

## Measurement

The primary metric is **net revenue per eligible paywall viewer**, reported by platform and combined.

Supporting metrics:

- Paywall views and checkout starts.
- Paid starts and paywall-to-paid conversion.
- Gross cash collected, refunds, fees when available, and net cash.
- Contracted or normalized monthly recurring revenue: weekly × 52/12, quarterly ÷ 3, annual ÷ 12, and monthly as charged.
- New, churned, and net normalized MRR.
- New subscriptions, cancellations, and net subscriber change.
- Term mix and revenue per active payer.
- Country split, with missing country reported separately rather than classified as international.

Report seven-day and thirty-day windows against their immediately preceding equal-length periods. Do not extrapolate a one-time launch step into a perpetual weekly compound-growth rate.

## Risk controls

- **Existing subscribers repriced accidentally:** require explicit legacy-cohort checks before activation and retain a before/after export of subscription pricing.
- **Displayed price differs from checkout:** validate each term in production-like checkout before opening traffic; the app clients must display store-returned localized prices.
- **Store propagation delay:** record separate activation timestamps and deploy web last.
- **Quarterly conversion falls after the largest increase:** monitor revenue per eligible paywall viewer and term mix, not starts alone.
- **Localized prices become unreasonable:** review the priority markets and correct obvious outliers before activation.
- **Offer conflict:** leave promotional offers unchanged and verify their checkout disclosures against the new standard price.
- **Analytics misstates the result:** maintain separate cash and normalized-MRR measures and keep unknown geography as its own bucket.

## Rollback

- Stripe/web: restore the legacy term-to-Price mapping for future checkouts and revert displayed prices. Do not alter subscriptions already created at the new prices.
- Apple and Google: restore the old prices for future subscribers using the store pricing tools. Do not migrate either legacy or new cohorts automatically.
- Preserve all Price IDs, activation timestamps, and cohort labels so post-rollback reporting remains attributable.

Rollback is immediate for a checkout mismatch, entitlement failure, or accidental existing-subscriber repricing. For commercial performance, roll back future new-customer prices if combined net revenue per eligible paywall viewer is more than 15% below the preceding 30-day baseline after both at least 14 days and 200 eligible paywall views. A conversion decline alone is not a rollback trigger if net revenue per eligible paywall viewer improves.

## Deliverables for implementation planning

- Exact Stripe Price IDs and server configuration locations.
- Exact Apple subscription IDs and price-change schedule.
- Exact Google product/base-plan IDs and legacy cohort settings.
- Paywall price and savings-copy changes.
- Prelaunch and postlaunch verification checklist.
- Launch log with platform activation timestamps.
- Weekly scorecard updates separating cash, normalized recurring revenue, active payers, term mix, and geography completeness.
