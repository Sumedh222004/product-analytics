# QuickKart — Product Growth & Marketplace Health: Insights Report

**Window:** Sep 2025 – Aug 2026 (12 months) · **As-of:** 31 Aug 2026
**Scale:** 23,670 customers · 161K delivered orders · ₹11.5 Cr GMV · 405K app sessions · 6 dark stores (Bengaluru)
**Data:** fully simulated, Blinkit-style quick-commerce dataset (see README). Every number below is reproducible from the SQL module referenced beside it.

---

## Executive summary

| # | Insight | Headline number | Module |
|---|---------|-----------------|--------|
| 1 | A bad **first order** is the single biggest churn driver | churn 83.5% vs 67.0% (+16.5 pp) | 14 |
| 2 | Two stores broke in May and are **bleeding customers** | on-time 73.7% → 30.6% post-May | 17 |
| 3 | The May promo bought **volume, not customers** | discount-led M1 retention 20.8% vs 54.6% | 13 |
| 4 | Channel budget is misallocated at the **activated-CAC** level | influencer ₹600/activated, payback month 4 | 10 |
| 5 | Margin per order **grows +48% with tenure** — accelerate it | ₹151 (M0) → ₹224 (M6+) | 16 |
| 6 | **Search is the high-intent path** the app under-uses | 56.6% vs 30.7% session conversion | 12 |

Topline: monthly GMV grew ₹14L → ₹1.73 Cr (Aug), active customers 891 → 6,724, AOV ₹649 → ₹752. Blended retention: M1 42.8%, M3 27.3%, M6 22.4%. August growth was healthy — the GMV bridge attributes +₹15.0L to actives (+₹10.3L), frequency (+₹3.0L) and basket (+₹1.7L) together, unlike May's promo-driven spike (+₹55.4L, of which +₹47.9L actives) that gave back ₹14.4L in June.

---

## 1. The first order decides everything (activation cliff)

**What the data shows (modules 11, 14):**
- 16.4% of first orders go wrong — arrive >5 min late or incomplete.
- Customers with a bad first order repeat within 28 days at **43.9%** vs **72.5%** after a clean first order (−28.6 pp).
- Long-run churn (>56 days inactive): **83.5%** vs **67.0%**.
- Time-to-value is fast when it works: 57% of eventual customers order the same day they sign up; 16.4% of signups never order at all.
- First-session behaviour matters too: signups who reach **add_to_cart in their first session** activate at 86.8% vs 70.4% for those who bounce at app open.

**Why it matters:** activation spend is wasted at the last metre. We pay CAC to bring a customer, then a late rider un-sells them.

**Recommendation:** treat the first order as an SLA class of its own — priority picking, surplus-buffer stock on the ~200 most-carted SKUs, no first-order dispatch during rider shortfall (offer a slot instead of a broken promise). Scenario: halving the bad-first rate (16.4% → 8.2%) converts ≈ 1,900 first orders a year from bad to good; at the observed +28.6 pp repeat lift that is ≈ **550 additional repeating customers/year**, worth ≈ ₹2.4L in 90-day contribution alone (avg ₹438/customer, module 10.D) before compounding retention.

## 2. Whitefield & Marathahalli broke in May — and demand noticed (marketplace health)

**What the data shows (module 17, 12.E, 14.C, 19):**
- Post-May, the two stressed stores: on-time **30.6%** (others: 73.7%), late >5 min on **29.7%** of orders, items missing on **9.8%**, cancellations 5.3% (2.4% elsewhere), avg rating **3.99** vs 4.44.
- Demand-side damage: cart → checkout continuation in those zones fell 84.1% → **78.9%** (other zones flat) — availability and slot failures are visible *inside the funnel*.
- Churn among customers who joined those zones May-onward: **80.9%** vs 68.0% elsewhere; 76.4% of the zones' customers now sit in the At-Risk/Critical health tiers (64.2% elsewhere).

**Why it matters:** these zones hold ~28% of the customer base. The May promo spiked demand into stores that had no capacity headroom — growth marketing and ops planned separately.

**Recommendation:** (1) immediate capacity: picker/rider shifts re-weighted to the 6-11 pm peak (module 17.C heatmap); (2) honest promises: dynamically widen the promised window when store load crosses a threshold — a kept 16-minute promise beats a broken 12; (3) gate future promo blasts on store capacity headroom; (4) win-back the affected cohort with a service-apology voucher once on-time is back above 70%.

## 3. The May promo bought volume, not customers (cohort quality)

**What the data shows (modules 13, 16):**
- May 2026 signups: 3,850 (+85% vs April) at +28% CAC; discount share of GMV hit 9.1% (baseline ~1.5-2%).
- May cohort M1 retention: **38.2%** vs 42.7% for other cohorts. The average hides the split: **discount-led** May customers (≥50% of their orders discounted — 48% of the cohort vs 26% normally) retained at **20.8%**; full-price-led May customers at **54.6%** — better than average.
- GMV bridge: May's +₹55.4L was +₹47.9L actives / +₹5.8L frequency / +₹1.6L basket; June gave back ₹14.4L as promo actives lapsed.

**Why it matters:** the promo worked for reach but recruited a segment whose economics don't clear CAC (module 10.C payback logic).

**Recommendation:** replace blanket 20%-off with a **laddered habit offer** (smaller discounts on orders 2 and 3, not order 1), bias promo distribution toward referral (its cohort retains at 55.6% M1) and toward lookalikes of full-price May converters; measure future promos on M1-retained customers per ₹, not signups per ₹.

## 4. Reallocate acquisition budget using activated CAC and payback (channel quality)

**What the data shows (module 10):**

| Channel | Signups | CAC | CAC / activated | Activation | M1 ret. | 90-day contribution | Payback month |
|---|---|---|---|---|---|---|---|
| Referral | 2,689 | ₹124 | ₹140 | 88.2% | 55.6% | ₹690 | 0 |
| Organic | 6,607 | — | — | 83.4% | 49.0% | ₹596 | 0 |
| Paid search | 5,122 | ₹280 | ₹374 | 74.9% | 38.7% | ₹439 | 1 |
| Paid social | 7,298 | ₹303 | ₹421 | 72.1% | 34.8% | ₹389 | 2 |
| Influencer | 1,954 | ₹388 | ₹600 | 64.7% | 30.4% | ₹336 | 4 |

**Why it matters:** on cost-per-signup the channels look comparable; on cost-per-*activated* and payback they are not. Influencer doesn't recover CAC for ~4 months while retaining 30%.

**Recommendation:** shift the influencer budget into scaling the referral program (double-sided incentive still costs ~⅓ of influencer CAC per activated customer); hold paid social to a ₹450/activated ceiling; keep paid search steady. Re-check after one quarter with the same scorecard.

## 5. Customers get more profitable with age — pull that curve forward (monetization)

**What the data shows (module 16.D):**
- Item margin per order climbs from **₹151 (month 0)** to ₹193 (months 3-5) to **₹224 (months 6+)**; margin rate 23.6% → 25.7%; AOV ₹649 → ₹752 over the year as the base matures.
- Driver: tenured customers attach high-margin categories — personal care, household — onto their grocery baskets.
- Overall contribution averages ₹130/order (after fees, discounts and an assumed ₹30 last-mile cost), which is what makes the module-10 paybacks work.

**Why it matters:** margin expansion is currently a *side effect* of tenure. Making the attach happen in months 1-2 turns it into a lever.

**Recommendation:** trigger cross-category nudges right after the 2nd delivered order (add-on aisle of trial-size personal-care/household SKUs, private-label first); success metric: % of month-1-2 orders containing a high-margin category, target the months-3-5 attach rate. Scenario: closing half the M0-2 → M3-5 margin gap (≈ ₹21/order) across ~45% of monthly orders ≈ **+₹2.0-2.2L contribution/month** at August volumes.

## 6. Search is the high-intent superhighway (task success)

**What the data shows (module 12):**
- Sessions using search convert at **56.6%** vs 30.7% for browse-only; converting sessions take 9.5 minutes open-to-order on average.
- Only ~55% of sessions use search. Android and iOS convert identically (41.0%) — no platform fire to fight.
- Overall funnel: 100 → 75.7 (product view) → 55.5 (cart) → 46.2 (checkout) → **41.0% (paid)**; the biggest single leak is view → cart.

**Recommendation:** make the search bar + "reorder my usuals" the first screen for returning users; pre-fill last basket. Measure: search adoption and view→cart step conversion.

---

## Portfolio-level read (modules 15, 16, 19)

- Value concentration is real: **Champions (23.9% of buyers) hold 60.7% of net spend**; Champions+Loyal = 31% of buyers, 72% of spend. The Healthy tier (15.1% of the base) generates 66.8% of the last-56-day spend.
- Lifecycle: 33.2% active / 11.5% at-risk / 55.3% churned (of ever-ordered, as of Aug 31). 14.7% of repeat customers have already demonstrated reactivation after a 56+ day gap — the win-back list is not a lost cause.
- After a 1-2★ rated order, customers reorder within 30 days at ≈79% vs ≈86% after a 5★ — small per-order, but it compounds across the 4-order monthly habit (module 18).

## What I would do next (with real data / more time)

1. **A/B test** the laddered promo vs blanket discount (my separate experimentation project covers the methodology).
2. Basket-affinity mining (market-basket / co-purchase lift) to pick the cross-sell SKUs for insight 5.
3. A simple churn-risk model (logistic on R/F/experience features) to rank the win-back list — the health score is a transparent heuristic, a model would sharpen it.
4. Unit-economics by zone including real last-mile costs instead of the flat ₹30 assumption.

## Number traceability

Every figure: `sql/1x_*.sql` module noted inline. Dataset is deterministic (seed 42), so re-running `data/generate_data.py` + the SQL reproduces these numbers exactly.
