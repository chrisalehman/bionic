# Modamily Global New-Subscriber Pricing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Launch the $199.99 annual / $99.99 quarterly / $49.99 monthly / $19.99 weekly ladder worldwide for new Stripe, Apple, and Google subscribers on August 16, 2026, while every existing subscriber keeps the price they already have.

**Architecture:** Stripe Checkout uses new immutable Price IDs, while webhook plan resolution retains both new and legacy IDs. The web paywall owns Stripe display amounts. iOS and Android keep their existing product/base-plan IDs and render localized prices returned by the stores. Apple preserved pricing and Google legacy price cohorts enforce grandfathering. A launch ledger and corrected scorecard separate cash from normalized MRR and make every platform activation attributable.

**Tech Stack:** React 16 / Create React App / Jest; Node.js 10 / Express / Stripe / Jest; Expo 54 / React Native 0.81 / react-native-iap 14 / Jest; App Store Connect; Google Play Console and Play Billing Lab; Python 3 / openpyxl / LibreOffice.

## Global Constraints

- Approved target date: **Sunday, August 16, 2026**. Operational assumption: **10:00 a.m. America/Los_Angeles**, with an engineer and the account owner available through 12:00 p.m.
- August 13 is code/config freeze, August 14 is prelaunch evidence capture, and August 15 is go/no-go.
- New subscribers only. Do not migrate, un-preserve, end, or otherwise move a legacy price cohort.
- Keep the current terms, entitlements, three-day annual trial, cancellation rules, plan order, quarterly default, and “Most Popular” badge.
- Keep active win-back economics: WINBACK99 and COMEBACK99 remain **$99.99 for year one, then $149.99/year**. Standard annual checkout becomes $199.99. Promo checkout must therefore use the legacy annual Stripe Price rather than subtracting $50 from the new annual Price.
- Do not change promo eligibility, free-trial eligibility, or the Mailgun A+C layout experiment in this launch.
- Never archive a legacy Stripe Price while a subscription or win-back checkout can still use it.
- Use fresh worktrees. The current ReactWeb and React-Native-App worktrees contain unrelated user changes.
- Every production billing change requires the final August 15 go/no-go. Preparation, tests, sandbox changes, and future Apple schedules may happen earlier.
- Record all timestamps in both UTC and America/Los_Angeles. Treat a platform as live only after a clean production catalog fetch shows the new price.

## Launch Calendar

| Date | Exit criterion |
|---|---|
| Aug 3–8 | Web, backend, native regression, and workbook changes pass locally in isolated worktrees. |
| Aug 9–12 | Stripe test Prices, Apple scheduled matrix, Google Billing Lab checks, and test purchases pass. |
| Aug 13 | Code/config freeze; all PRs approved; live Stripe Price IDs created but not mapped. |
| Aug 14 | Production exports, store matrices, rollback commit, and release bundle captured. |
| Aug 15 | Go/no-go signed. Any price mismatch, entitlement failure, or unproven grandfathering is a no-go. |
| Aug 16, 10:00 a.m. PT | Google price activation, mobile visibility checks, then Stripe/web deploy and two-hour verification. |
| Aug 23 | Seven-day reliability and commercial review. |
| Sep 15 | Thirty-day review using complete data through Sep 14. |

---

### Task 1: Create isolated implementation worktrees and the launch ledger

**Files:**
- Create: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`
- Modify: `/Users/ivanfatovic/workspace/bionic/.bionic/memory/context.md`

- [ ] **Step 1: Refresh clean base refs without touching dirty worktrees**

```bash
git -C /Users/ivanfatovic/workspace/ReactWeb fetch origin
git -C /Users/ivanfatovic/workspace/React-Native-App fetch origin
git -C /Users/ivanfatovic/workspace/backend2019 fetch origin
```

Expected: all three fetches exit 0. Do not stash or clean the current worktrees.

- [ ] **Step 2: Create dedicated worktrees**

```bash
mkdir -p /Users/ivanfatovic/workspace/worktrees
git -C /Users/ivanfatovic/workspace/ReactWeb worktree add /Users/ivanfatovic/workspace/worktrees/pricing-web -b codex/pricing-2026-08-16 7d239eaae8da9a6e40f92361fd23062a05607c03
git -C /Users/ivanfatovic/workspace/React-Native-App worktree add /Users/ivanfatovic/workspace/worktrees/pricing-native -b codex/pricing-2026-08-16 1ed7656e2834c6c29fec5e215d17f9ed72eb3a5d
git -C /Users/ivanfatovic/workspace/backend2019 worktree add /Users/ivanfatovic/workspace/worktrees/pricing-backend -b codex/pricing-2026-08-16 origin/master
```

Expected: each new worktree reports a clean status. If either fixed source SHA is no longer the intended product baseline, stop and record the replacement SHA before creating that worktree.

- [ ] **Step 3: Write the launch ledger with immutable identifiers**

The ledger must contain these known identifiers and mark each execution field `NOT EXECUTED` until the action occurs:

```markdown
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
```

- [ ] **Step 4: Record baseline exports**

Attach or link these files from a dated, access-controlled launch folder outside Git:

- Stripe active subscriptions export with subscription ID, Price ID, amount, currency, status, current-period end, and customer country when available.
- App Store Connect current and future subscription-price CSV exports for all four product IDs.
- Google Play base-plan regional-price export/screenshots and the current legacy-price-point view for all four base plans.
- Active-at-date subscriber counts by platform. Do not use a six-month Google total as an active count.

- [ ] **Step 5: Commit the planning artifacts**

```bash
git add docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md .bionic/memory/context.md
git commit -m "docs: add August 16 pricing launch ledger"
```

---

### Task 2: Change the web ladder while preserving the existing win-back promise

**Files:**
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/constants/subscriptionTypes.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/constants/paywallLayout.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/components/modals/ModamilyAppUpgrade.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/utils/ga4StripeReturn.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/utils/ga4Purchase.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/utils/planSavings.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/utils/ga4StripeReturn.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/utils/ga4Purchase.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/utils/ga4PurchaseSource.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/components/modals/upgradeCtaState.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/components/modals/upgradeDisclosure.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/components/modals/upgradePaywallEvents.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/components/modals/upgradePlanCardOffer.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/components/modals/upgradeOfferBanner.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/components/settings/membershipPage.test.js`
- Create: `/Users/ivanfatovic/workspace/worktrees/pricing-web/src/constants/subscriptionTypes.test.js`

- [ ] **Step 1: Add a failing canonical-ladder test**

```javascript
import SubscriptionOptions from "./subscriptionTypes";

it("pins the August 16 new-subscriber ladder", () => {
  expect(SubscriptionOptions).toEqual([
    { duration: 0.25, price: 19.99, totalCost: 19.99, type: "1w" },
    { duration: 1, price: 49.99, totalCost: 49.99, type: "1m" },
    { duration: 3, price: 33.33, totalCost: 99.99, type: "3m" },
    { duration: 12, price: "16.67", totalCost: 199.99, type: "12m" },
  ]);
});
```

- [ ] **Step 2: Update all non-offer assertions to the new ladder and run the focused suite**

Expected savings against weekly are monthly 42%, quarterly 62%, and annual 81%.

```bash
CI=true npm test -- --watchAll=false src/constants/subscriptionTypes.test.js src/utils/planSavings.test.js src/utils/ga4StripeReturn.test.js src/utils/ga4Purchase.test.js src/utils/ga4PurchaseSource.test.js src/components/modals/upgradeCtaState.test.js src/components/modals/upgradeDisclosure.test.js src/components/modals/upgradePaywallEvents.test.js src/components/modals/upgradePlanCardOffer.test.js src/components/modals/upgradeOfferBanner.test.js src/components/settings/membershipPage.test.js
```

Expected: failures show the old standard prices. Offer-specific assertions must still expect $99.99 first year and $149.99 renewal.

- [ ] **Step 3: Replace the canonical ladder**

```javascript
export default [
  { duration: 0.25, price: 19.99, totalCost: 19.99, type: "1w" },
  { duration: 1, price: 49.99, totalCost: 49.99, type: "1m" },
  { duration: 3, price: 33.33, totalCost: 99.99, type: "3m" },
  { duration: 12, price: "16.67", totalCost: 199.99, type: "12m" },
];
```

- [ ] **Step 4: Decouple win-back display terms from the standard annual price**

Replace the numeric `WINBACK_OFFERS` values with the actual offer contract:

```javascript
const WINBACK_OFFERS = {
  WINBACK99: { amountOff: 50, listTotal: 149.99 },
  COMEBACK99: { amountOff: 50, listTotal: 149.99 },
};
```

In `buildOfferBanner`, validate that the annual plan exists, then derive all offer text from `offer.listTotal - offer.amountOff`. A promo card must show `$8.33/mo`, `$99.99 first year`, and `then $149.99/yr`; a normal annual card must show `$16.67/mo` and `$199.99 total`.

- [ ] **Step 5: Correct the false June 20 comment without changing layout behavior**

Change the comment in `paywallLayout.js` to state that quarterly became material around June 20; do not claim the product was introduced then. Keep `COLUMN_4ROW_QUARTERLY_DEFAULT`, order `12m, 3m, 1m, 1w`, quarterly default, and quarterly badge unchanged.

- [ ] **Step 6: Make GA4 report actual promo cash and the pricing cohort**

Extend `trackPurchase` with a `pricing_cohort` parameter and include it in the purchase event. In `ga4StripeReturn.js`, accept only `new_2026_08_16` and `winback_legacy_offer` from the server-stamped `pc` query parameter. Use $99.99 for a `12m` win-back purchase and the canonical plan total for a standard purchase. Default older return URLs to `legacy_or_unknown`; remove `pc` when cleaning the URL.

Add assertions that a standard annual return books $199.99 with `new_2026_08_16`, while a promo annual return books $99.99 with `winback_legacy_offer`.

- [ ] **Step 7: Run the focused suite, full suite, and production build**

```bash
CI=true npm test -- --watchAll=false src/constants/subscriptionTypes.test.js src/utils/planSavings.test.js src/utils/ga4StripeReturn.test.js src/utils/ga4Purchase.test.js src/utils/ga4PurchaseSource.test.js src/components/modals/upgradeCtaState.test.js src/components/modals/upgradeDisclosure.test.js src/components/modals/upgradePaywallEvents.test.js src/components/modals/upgradePlanCardOffer.test.js src/components/modals/upgradeOfferBanner.test.js src/components/settings/membershipPage.test.js
CI=true npm test -- --watchAll=false
npm run build:release
```

Expected: all tests pass; build completes; generated paywall displays the four new standard prices and unchanged win-back terms.

- [ ] **Step 8: Commit**

```bash
git add src
git commit -m "feat(web): set August 16 new-subscriber prices"
```

---

### Task 3: Keep Stripe legacy IDs resolvable and route promo checkout to the legacy annual Price

**Files:**
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/config/config.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/api/stripe.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/api/api.router.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/__tests__/stripeConfig.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/__tests__/checkoutPromoAllowlist.test.js`
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/__tests__/checkoutUpgradeSource.test.js`
- Create: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/__tests__/checkoutPriceCohort.test.js`

- [ ] **Step 1: Add failing tests for current, legacy, and promo routing**

The route-level test must assert:

```javascript
expect(fullPriceAnnual.line_items).toEqual([
  { price: "price_12m_new", quantity: 1 },
]);
expect(fullPriceAnnual.metadata).toEqual({
  upgrade_source: "organic",
  pricing_cohort: "new_2026_08_16",
  plan_type: "12m",
  price_id: "price_12m_new",
});

expect(winbackAnnual.line_items).toEqual([
  { price: "price_12m_legacy", quantity: 1 },
]);
expect(winbackAnnual.metadata.pricing_cohort).toBe("winback_legacy_offer");
expect(monthly.line_items).toEqual([
  { price: "price_1m_new", quantity: 1 },
]);
expect(fullPriceAnnual.success_url).toContain("pc=new_2026_08_16");
expect(winbackAnnual.success_url).toContain("pc=winback_legacy_offer");
```

Also assert that both `price_12m_new` and `price_12m_legacy` resolve to `12m` when the webhook calls `getPlanById`.

- [ ] **Step 2: Run the tests and prove they fail**

```bash
npm test -- --runInBand __tests__/stripeConfig.test.js __tests__/checkoutPromoAllowlist.test.js __tests__/checkoutUpgradeSource.test.js __tests__/checkoutPriceCohort.test.js
```

Expected: failures show no legacy plan map, promo checkout using the standard map, and missing pricing metadata.

- [ ] **Step 3: Preserve the existing maps explicitly**

Add `testLegacyPlans` and `liveLegacyPlans` beside the current maps. Seed them with the exact IDs already in `config/config.js`:

```javascript
liveLegacyPlans: {
  "1w": "price_1IJ7u3ALfCP0Km8w3HOUNuZd",
  "1m": "price_1QyfQpALfCP0Km8wK0rdygqU",
  "3m": "price_1IJQvPALfCP0Km8wi13vhjWJ",
  "6m": "plan_Fm9c1zBu3LYplE",
  "12m": "price_1IJQx5ALfCP0Km8wgcljJydj",
},
```

Copy the present test-map IDs into `testLegacyPlans`. The new `testPlans` and `livePlans` receive the new Price IDs created in Task 6. Keep the unused 6m legacy entry resolvable but never show it on the four-plan paywall.

- [ ] **Step 4: Export both checkout and legacy maps from `api/stripe.js`**

Use `plans` only for new standard checkout. Export `legacyPlans` for promo checkout and `planTypeById` for webhook resolution:

```javascript
const planTypeById = {};
Object.keys(legacyPlans).forEach(function (type) {
  planTypeById[legacyPlans[type]] = type;
});
Object.keys(plans).forEach(function (type) {
  planTypeById[plans[type]] = type;
});

exports.plans = plans;
exports.legacyPlans = legacyPlans;
exports.planTypeById = planTypeById;
```

Fail fast in production if either `livePlans` or `liveLegacyPlans` is empty.

- [ ] **Step 5: Select the checkout Price after promo eligibility is known**

In `/checkout-create-session`, compute `promotionCodeId` first. Then use:

```javascript
const standardPriceId = stripe.plans[priceType];
const priceId = promotionCodeId
  ? stripe.legacyPlans["12m"]
  : standardPriceId;
const pricingCohort = promotionCodeId
  ? "winback_legacy_offer"
  : "new_2026_08_16";
```

Replace `getPlanById` with a `stripe.planTypeById[planId]` lookup. Keep the no-trial-on-promo rule. Extend session metadata with `pricing_cohort`, `plan_type`, and the actual `price_id` used.

Append `pc=${pricingCohort}` to the success URL so the return-leg GA4 event records the actual cohort and cash amount. Keep `priceType` and `upgradeSource` server-stamped as they are now.

- [ ] **Step 6: Persist Stripe currency on successful checkout**

The current webhook writes Stripe `price` but leaves `currency` null. Set it from the Checkout Session, defaulting only when Stripe explicitly reports USD:

```javascript
const checkoutCurrency = session.currency
  ? String(session.currency).toUpperCase()
  : null;
```

Write `currency: checkoutCurrency` on create and `user.subscription.currency = checkoutCurrency` on update. Add assertions to `checkoutPriceCohort.test.js`; do not infer a nonreported currency.

- [ ] **Step 7: Run focused and full backend suites**

```bash
npm test -- --runInBand __tests__/stripeConfig.test.js __tests__/checkoutPromoAllowlist.test.js __tests__/checkoutUpgradeSource.test.js __tests__/checkoutPriceCohort.test.js
npm test -- --runInBand
```

Expected: all tests pass under the repository’s Node-compatible syntax.

- [ ] **Step 8: Commit the code before inserting live IDs**

```bash
git add api config __tests__
git commit -m "feat(stripe): preserve legacy pricing cohorts"
```

---

### Task 4: Prove the current iOS and Android clients render the new store prices dynamically

**Files:**
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-native/src/screens/AccountProfile/__tests__/Upgrade.paywallSavings.test.js`
- Modify only if the tests expose a defect: `/Users/ivanfatovic/workspace/worktrees/pricing-native/src/screens/AccountProfile/Upgrade.js`
- Modify only if the tests expose a defect: `/Users/ivanfatovic/workspace/worktrees/pricing-native/src/utils/subscriptionOffers.js`

- [ ] **Step 1: Replace stale U.S. fixtures with the approved ladder**

Android fixtures use 19,990,000 / 49,990,000 / 99,990,000 / 199,990,000 micros. iOS fixtures use 19.99 / 49.99 / 99.99 / 199.99. The expected mapped output is:

```javascript
expect(byDuration(mapped, "Weekly")).toMatchObject({
  priceText: "$19.99 Per Week",
  savingsText: "",
});
expect(byDuration(mapped, "Monthly")).toMatchObject({
  priceText: "$49.99 Per Month",
  savingsText: "42% savings",
});
expect(byDuration(mapped, "Quarterly")).toMatchObject({
  priceText: "$99.99 Per Quarter",
  monthlyPriceText: "$33.33/mo",
  savingsText: "62% savings",
});
expect(byDuration(mapped, "Yearly")).toMatchObject({
  priceText: "$199.99 Per Year",
  monthlyPriceText: "$16.67/mo",
  savingsText: "81% savings",
});
```

- [ ] **Step 2: Add localized-price regression cases**

Add one iOS fixture using `199,99 €` / numeric `199.99` and one Android fixture using `£199.99` / 199,990,000 micros. Assert that the original currency symbol and decimal separator remain in `priceText` and `monthlyPriceText`; do not add a USD table to native code.

- [ ] **Step 3: Run the focused test before production changes**

```bash
npm test -- --runInBand src/screens/AccountProfile/__tests__/Upgrade.paywallSavings.test.js src/utils/__tests__/subscriptionOffers.test.js
```

Expected: the new fixture assertions pass without production-code changes. If they fail, fix only the store-payload formatting defect exposed by the test.

- [ ] **Step 4: Run the full suite and commit**

```bash
npm test -- --runInBand
git add src/screens/AccountProfile/__tests__/Upgrade.paywallSavings.test.js src/screens/AccountProfile/Upgrade.js src/utils/subscriptionOffers.js
git commit -m "test(paywall): pin August 16 store price rendering"
```

---

### Task 5: Correct the growth model and add cash-versus-MRR launch reporting

**Files:**
- Create: `/Users/ivanfatovic/workspace/bionic/scripts/update_modamily_growth_model_pricing.py`
- Create: `/Users/ivanfatovic/workspace/bionic/tests/test_modamily_growth_model_pricing.py`
- Read: `/Users/ivanfatovic/Claude-Work/Outputs/modamily-growth-model.xlsx`
- Create: `/Users/ivanfatovic/Claude-Work/Outputs/modamily-growth-model-pricing-launch-2026-08-16.xlsx`

- [ ] **Step 1: Write failing workbook-structure tests**

Tests must load formulas and cached values separately and assert:

- `Pricing Ladder!G5:G9` is 38%, 27%, 23%, 8%, 4% for annual, quarterly, monthly, weekly, legacy.
- `Pricing Ladder!H5:H8` normalizes the four new-plan shares to 100%; legacy is excluded from new-subscriber ARPU.
- `Path to $30K!D8` links to the corrected new-ladder blended monthly ARPU.
- `Weekly Scorecard` has distinct columns for gross cash, fees, refunds, net cash, normalized new MRR, active payers, four term-start counts, and U.S./non-U.S./unknown geography.
- Net revenue per eligible paywall viewer is a formula, not a typed result.

- [ ] **Step 2: Run the tests and prove the source workbook fails**

```bash
/Users/ivanfatovic/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest tests/test_modamily_growth_model_pricing.py
```

Expected: failures identify the 60/25/10/5 payer mix and missing scorecard columns.

- [ ] **Step 3: Implement an idempotent workbook transformation**

Preserve the source file. Write the dated output with these exact scorecard headers:

```text
Week ending | Platform | Pricing cohort | Gross cash collected ($) |
Refunds ($) | Fees ($) | Net cash ($) | Normalized new MRR ($) |
Active payers | Eligible paywall viewers | Paywall views | Paid starts |
Weekly starts | Monthly starts | Quarterly starts | Annual starts |
U.S. paid starts | Non-U.S. paid starts | Country unknown |
Net revenue / eligible viewer ($) | 28d rolling net cash ($) | On track vs cash target?
```

Use formulas:

```excel
G5 = D5-E5-F5
T5 = IFERROR(G5/J5,0)
U5 = SUMIFS($G:$G,$B:$B,B5,$A:$A,">="&A5-27,$A:$A,"<="&A5)
V5 = IF(U5>=Assumptions!$B$20,"YES","NO")
```

In `Pricing Ladder`, add Legacy at approximately $32/month, mark the 38% annual share as a wide estimate based on only four annual charges, and remove claims that the price change is purely an ARPU lever. Keep `Path to $30K` explicitly denominated in normalized MRR and label the Weekly Scorecard target view as cash.

- [ ] **Step 4: Match workbook style and document assumptions**

Copy existing row/header styles. Use blue font for manual inputs, black for formulas, yellow fill for editable assumptions, and comments that identify the payer-mix source as the user’s June 2–August 2 Stripe transaction reconstruction. Do not overwrite existing formulas outside the named sheets.

- [ ] **Step 5: Recalculate and verify zero formula errors**

```bash
/Users/ivanfatovic/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 /Users/ivanfatovic/.codex/plugins/cache/anthropic-agent-skills/document-skills/local/skills/xlsx/scripts/recalc.py /Users/ivanfatovic/Claude-Work/Outputs/modamily-growth-model-pricing-launch-2026-08-16.xlsx 60
/Users/ivanfatovic/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3 -m unittest tests/test_modamily_growth_model_pricing.py
```

Expected: recalc returns `status: success`, `total_errors: 0`; all workbook tests pass.

- [ ] **Step 6: Commit the transformation and tests**

```bash
git add scripts/update_modamily_growth_model_pricing.py tests/test_modamily_growth_model_pricing.py
git commit -m "feat(model): separate pricing cash from normalized MRR"
```

---

### Task 6: Create Stripe Prices and verify Checkout in test mode

**Files:**
- Modify: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/config/config.js`
- Modify: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`

- [ ] **Step 1: Create four test-mode Prices on the existing products**

Create recurring USD Prices with these exact unit amounts and intervals:

| Term | Unit amount | Interval | Interval count |
|---|---:|---|---:|
| Weekly | 1999 | week | 1 |
| Monthly | 4999 | month | 1 |
| Quarterly | 9999 | month | 3 |
| Annual | 19999 | year | 1 |

Add metadata `pricing_launch=2026-08-16` and `plan_type=1w|1m|3m|12m`. Use the same Stripe Product IDs as the corresponding legacy Prices.

- [ ] **Step 2: Put the returned test Price IDs into `testPlans`**

Record every returned `price_...` ID in the launch ledger first, then replace only `testPlans`. Never replace `testLegacyPlans`.

- [ ] **Step 3: Run all four test checkouts**

For each term, assert the hosted Checkout amount and interval, complete one test purchase, and verify:

- `checkout.session.completed` grants the existing entitlement.
- `metadata.plan_type`, `metadata.price_id`, and `metadata.pricing_cohort` are present.
- A canceled test checkout grants no entitlement.
- WINBACK99 annual uses the legacy test annual Price, charges the unchanged test offer, and has no three-day trial.
- Standard annual uses the new test annual Price and retains the three-day trial.

- [ ] **Step 4: Create the four live Prices without switching checkout**

Repeat Step 1 in live mode. Record returned IDs in the launch ledger and `livePlans`, but do not deploy that commit yet. Keep each legacy Price active.

- [ ] **Step 5: Run config tests and commit the generated IDs**

```bash
npm test -- --runInBand __tests__/stripeConfig.test.js __tests__/checkoutPriceCohort.test.js
git add config/config.js
git commit -m "config(stripe): add August 16 price IDs"
```

Expected: test/live IDs are distinct; new and legacy maps are complete; no ID is blank or reused across modes.

---

### Task 7: Schedule Apple prices with explicit preservation and verify sandbox behavior

**Files:**
- Modify: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`

- [ ] **Step 1: Schedule each existing Apple subscription product for August 16**

For each of the four product IDs, open Subscriptions → subscription group → product → Subscription Prices → add price. Use the United States as the base storefront, choose the approved anchor, accept Apple’s comparable prices for all enabled storefronts, and choose **“Keep the current price for existing subscribers.”**

- [ ] **Step 2: Review the generated matrix before confirming**

Record the displayed amount and currency for United States, United Kingdom, Canada, Australia, Germany, France, Italy, Spain, and Netherlands. Confirm no existing future schedule is being overwritten. Export the planned prices CSV, then confirm the schedule.

- [ ] **Step 3: Prove preservation in the UI**

Open View all Subscription Pricing and capture evidence that the legacy starting price remains listed for existing subscribers and the future price is dated August 16. Do not use “Un-preserve prices.”

- [ ] **Step 4: Test the production client against Apple sandbox**

Using a Sandbox Apple Account and a development/TestFlight build:

- Fetch all four product IDs and capture localized price strings.
- Complete a new annual sandbox purchase and verify the three-day trial and entitlement.
- Simulate renewal and verify entitlement remains active.
- Simulate interrupted/canceled purchase and verify no entitlement.
- Switch the sandbox storefront to one priority non-U.S. market and verify localized display.

Apple notes that catalog metadata may take up to one hour to appear in sandbox; wait for the catalog rather than changing client constants.

- [ ] **Step 5: Record evidence and leave active offers unchanged**

Record the scheduled-change timestamp, CSV hash, screenshots, sandbox transaction IDs, and active introductory/promotional offers in the launch ledger.

---

### Task 8: Verify Google with Billing Lab and prepare the production base-plan edits

**Files:**
- Modify: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`

- [ ] **Step 1: Capture each active base plan before editing**

For `sub_12m/p1y`, `sub_3m/p3m`, `sub_1m/p1m`, and `sub_1w/p1w`, record current regional prices, active offers, grace period, account hold, resubscribe behavior, and existing legacy-price cohorts.

- [ ] **Step 2: Test the new anchors with Play Billing Lab**

Use a license tester and Billing Lab’s subscription price-change tool. Test the four U.S. anchors without changing production. Then switch Billing Lab to one priority non-U.S. region and verify the purchase sheet displays a localized amount.

- [ ] **Step 3: Run entitlement edge cases**

Complete, cancel, interrupt, and decline test purchases. Verify successful purchases grant the same entitlement, pending/declined purchases do not, and SubscriptionPurchaseV2 reports product ID, region, price, and currency.

- [ ] **Step 4: Prepare the launch-day edit checklist**

For each base plan, the August 16 action is: edit regional price → select all enabled countries/regions → enter the U.S. anchor → apply Google’s one-time conversion → review priority markets → save. Saving creates a legacy price cohort automatically for existing subscribers. Do not choose “End legacy price cohort.”

- [ ] **Step 5: Record evidence**

Add Billing Lab screenshots, license-test order IDs, priority-market amounts, and the exact Console navigation path to the launch ledger.

---

### Task 9: Build the production release bundle and freeze rollback artifacts by August 14

**Files:**
- Replace generated bundle: `/Users/ivanfatovic/workspace/worktrees/pricing-backend/build/`
- Modify: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`

- [ ] **Step 1: Rebase/merge reviewed web and backend work onto current production bases**

Resolve only pricing-related conflicts. Re-run the full web and backend suites after integration.

- [ ] **Step 2: Build the release-tagged web bundle**

```bash
cd /Users/ivanfatovic/workspace/worktrees/pricing-web
npm run build:release
```

If Sentry credentials are available, upload source maps from this exact commit with `npm run sentry:sourcemaps`.

- [ ] **Step 3: Copy the served bundle into backend2019**

```bash
rsync -a --delete /Users/ivanfatovic/workspace/worktrees/pricing-web/build/ /Users/ivanfatovic/workspace/worktrees/pricing-backend/build/
```

Verify `build/index.html` references the newly generated hashed assets and no referenced file is missing.

- [ ] **Step 4: Run final code gates**

```bash
cd /Users/ivanfatovic/workspace/worktrees/pricing-web
CI=true npm test -- --watchAll=false
npm run build:release
cd /Users/ivanfatovic/workspace/worktrees/pricing-backend
npm test -- --runInBand
```

- [ ] **Step 5: Commit the bundle and record rollback SHAs**

```bash
git add build
git commit -m "chore(web): bundle August 16 pricing release"
```

Record in the launch ledger:

- prelaunch backend production SHA;
- pricing backend SHA;
- web source SHA embedded in Sentry release;
- rollback commit that restores the legacy `livePlans` mapping and old bundle while retaining both webhook lookup maps.

- [ ] **Step 6: Freeze August 14 evidence**

Repeat the three platform exports from Task 1 and compare subscriber counts and legacy identifiers. Any unexplained Price ID, base-plan change, or Apple schedule drift blocks go/no-go.

---

### Task 10: Hold go/no-go on August 15

**Files:**
- Modify: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`

- [ ] **Step 1: Require every technical gate**

All automated suites pass; all four terms have successful test purchases; canceled/failed purchases grant no entitlement; legacy Stripe IDs resolve; Apple preservation is visible; Google Billing Lab tests pass; localized amounts were reviewed; web promo and standard annual amounts differ correctly.

- [ ] **Step 2: Require every operational gate**

Confirm the account owner, engineer, Apple device, Android device, Stripe live access, App Store Connect access, Google Play access, EC2 deploy access, and rollback SHA will be available from 9:30 a.m.–12:00 p.m. PT Sunday.

- [ ] **Step 3: Sign the decision**

Record `GO` only if no blocker remains. A price-display mismatch, unverified grandfathering, broken entitlement, missing rollback, or active email promise that disagrees with the $99.99/$149.99 win-back path is an automatic `NO-GO`.

---

### Task 11: Execute the August 16 launch in propagation-safe order

**Files:**
- Modify: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`
- Modify: `/Users/ivanfatovic/Claude-Work/Outputs/modamily-growth-model-pricing-launch-2026-08-16.xlsx`

- [ ] **Step 1: Start at 9:30 a.m. PT with health and catalog checks**

Verify current web checkout, API health, Apple catalog, Google catalog, Stripe webhook health, and PM2 status. Record the result before any change.

- [ ] **Step 2: Confirm Apple’s scheduled prices are visibly live**

Fetch all four products from a clean production client. Record Apple’s actual visible-production timestamp and U.S./priority-market values. If Apple is not live, pause; do not deploy web.

- [ ] **Step 3: Save Google’s four production base-plan prices**

Apply the prepared regional matrices. For each base plan, immediately verify that Play created a legacy cohort and that the current price is visible to a clean new license/account context. Record actual visibility timestamps. Never end the legacy cohorts.

- [ ] **Step 4: Deploy backend and web only after both mobile catalogs are live**

Merge the pricing backend branch to `master`. On the production box run the repository deployment script:

```bash
cd /home/ubuntu/server/backend2019
bash scripts/deploy.sh
```

Expected: fast-forward pull, JavaScript syntax checks pass, API reloads, PM2 reports online, and local API health returns HTTP 200.

- [ ] **Step 5: Complete one real low-risk standard purchase per platform**

Use the weekly plan where a real charge is necessary. Confirm displayed amount equals charged amount, entitlement activates, and the transaction carries platform/term/currency/country where available. Refund the test purchase through the platform’s normal process and record the refund rather than deleting evidence.

- [ ] **Step 6: Verify annual standard and win-back checkout without charging both**

Open Checkout Sessions far enough to verify:

- Standard annual: $199.99, three-day trial, new Price ID, `new_2026_08_16` cohort.
- WINBACK99/COMEBACK99 annual: $99.99 today, $149.99 renewal disclosure, legacy annual Price ID, no trial, `winback_legacy_offer` cohort.

- [ ] **Step 7: Verify one legacy subscription per platform**

Use platform-supported renewal simulation or inspect the next invoice/renewal record. Confirm the legacy amount and identifier did not change. A single accidental repricing triggers immediate rollback.

- [ ] **Step 8: Populate the first launch scorecard rows**

Enter one `new_2026_08_16` row per platform. Keep gross cash, net cash, and normalized new MRR separate; classify missing country as unknown, not non-U.S.

- [ ] **Step 9: Close the two-hour launch window**

Record final API health, checkout error rate, entitlement errors, store visibility, standard/promo annual terms, and open incidents. Mark launch complete only when all three platforms pass.

---

### Task 12: Monitor, review, and roll back by explicit rules

**Files:**
- Modify: `/Users/ivanfatovic/Claude-Work/Outputs/modamily-growth-model-pricing-launch-2026-08-16.xlsx`
- Modify: `/Users/ivanfatovic/workspace/bionic/docs/superpowers/runbooks/2026-08-16-pricing-launch-log.md`

- [ ] **Step 1: Check reliability at +2h, +24h, and +72h**

Review checkout failures, store purchase failures, entitlement errors, refund requests, subscriber complaints, and any standard/promo price mismatch by platform and term.

- [ ] **Step 2: Perform the August 23 seven-day review**

Compare August 16–22 with August 9–15. Report net revenue per eligible paywall viewer, gross/net cash, normalized new MRR, conversion, term mix, active payers, and U.S./non-U.S./unknown country completeness. Do not use charge count as the headline.

- [ ] **Step 3: Perform the September 15 thirty-day review**

Use complete August 16–September 14 data against the immediately preceding 30 days. Keep the annual-share estimate qualified until actual active subscription counts by plan are available.

- [ ] **Step 4: Apply immediate technical rollback rules**

For any display/charge mismatch, entitlement failure, or existing-subscriber repricing:

1. Restore the legacy Stripe `livePlans` mapping and old web bundle for future checkout; keep both mapping sets resolvable.
2. Restore old Google prices for future purchasers; do not end or migrate any cohort.
3. Schedule Apple’s old prices as the next available price for future purchasers; do not un-preserve legacy subscribers.
4. Record which new-price subscriptions remain and preserve their identifiers for reporting.

- [ ] **Step 5: Apply the commercial rollback rule no earlier than eligible**

Roll back future new-customer prices only if combined net revenue per eligible paywall viewer is more than 15% below the preceding 30-day baseline after both 14 days and 200 eligible paywall views. A lower conversion rate alone is not a rollback trigger.

---

## Final Verification Checklist

- [ ] Standard U.S. prices are 199.99 / 99.99 / 49.99 / 19.99 on all applicable platforms.
- [ ] Apple and Google priority-market localized values match reviewed matrices.
- [ ] Existing subscribers remain on legacy prices.
- [ ] Stripe webhooks resolve both legacy and new Price IDs.
- [ ] Promo annual remains 99.99 first year and 149.99 renewal; standard annual is 199.99.
- [ ] Quarterly remains preselected and “Most Popular.”
- [ ] Savings display is 42% monthly, 62% quarterly, 81% annual against weekly.
- [ ] Entitlements and failed/canceled purchase behavior are unchanged.
- [ ] Cash, normalized MRR, active payer, term, platform, cohort, and geography reporting are distinct.
- [ ] Launch ledger contains timestamps, evidence, release SHAs, and rollback SHAs.

## Plan Self-Review

- [ ] Every approved design requirement maps to a task or explicit verification gate.
- [ ] No task migrates existing subscribers or ends legacy cohorts.
- [ ] All production-code changes begin with a failing test and end with focused plus full verification.
- [ ] Native production code remains unchanged unless a store-payload regression test proves a defect.
- [ ] No code block contains a fake production Price ID; generated IDs are captured from Stripe before configuration.
- [ ] Scan the plan for unresolved implementation markers and remove them.
- [ ] Confirm every named function, file, test command, product ID, base-plan ID, and legacy Stripe Price ID against the repositories and consoles before execution.
