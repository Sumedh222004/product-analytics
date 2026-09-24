# Interview Q&A — defend every part of this project

22 questions you should expect, with strong answers. Practice saying these
out loud; in the interview, lead with the number, then the reasoning.

---

### Walkthrough & framing

**1. Walk me through this project in 90 seconds.**
"I built and analyzed a Blinkit-style quick-commerce business end to end. I
simulated 12 months of realistic data — 23.7K customers, 161K orders, a 1.45M
event funnel log — loaded it into a SQL Server star schema, and wrote ten
T-SQL modules covering the full product-metrics stack: acquisition and CAC
payback, activation, funnel, retention cohorts, churn drivers, RFM, GMV
decomposition, marketplace ops health, HEART, and customer/product health
scores. The output is six decision-ready insights and a 5-page Power BI
dashboard. The headline finding: first-order experience is the biggest
retention lever — a late or incomplete first delivery drops 28-day repeat
from 72% to 44%."

**2. Why simulated data? Isn't that a weakness?**
"I flipped it into a strength. I injected known causal patterns — a store
capacity failure, a deal-hunter promo cohort, channel quality gaps — and then
had to *recover* them with SQL, which means I can verify my analysis against
ground truth. Public datasets can't do that, and they never have event logs +
orders + spend + ops in one place. The trade-off I'm honest about: my data is
cleaner than reality — no tracking loss, no schema drift — so the data-quality
module (03) is lighter than a real job would demand."

**3. What was the hardest analytical part?**
"The GMV bridge. Decomposing a MoM change into actives × frequency × AOV
sounds simple until you make the attribution exact — I used sequential
substitution and kept a `check_diff` column proving the three effects sum to
the total. And it changed the story: May's +₹55L looked great until the
bridge showed ₹48L of it was one-off promo actives that lapsed in June."

### Definitions (they WILL drill these)

**4. Why is activation 'first order within 7 days'?**
"Empirically, 57% of eventual first orders happen same-day and ~79% within a
day — by day 7 the habit window has effectively closed; late activators
(8-45d) are only ~8% of buyers. Also it's operationally actionable: a 7-day
window gives CRM a concrete deadline for onboarding nudges."

**5. Why 56 days for churn and not 30?**
"Actives here order ~3.4x/month, so the median inter-order gap is roughly a
week to ten days. 28 days of silence is 'at risk'; 56 — about 2x a slow
cycle — is a broken habit. With 30 days I'd over-flag vacationing monthly
shoppers. In a real role I'd fit this from inter-purchase-time distributions
per segment rather than one global cutoff."

**6. GMV vs net revenue vs contribution — which did you use where?**
"GMV (pre-discount basket value of delivered orders) for growth and retention
because it's the demand signal; net revenue (− discounts + fees) for what we
bill; contribution (item margin + fees − discounts − ₹30 assumed last-mile)
for CAC payback and LTV logic, because you can't pay marketing with GMV. The
₹30 is a documented assumption — I'd replace it with actual rider cost per
delivery and re-run sensitivity."

**7. Your retention denominator is all signups, not activated users. Why?**
"Deliberate. Cohort-on-signups makes M0 carry activation quality, so a
channel that signs up window-shoppers looks bad from column one. If I
denominated on first-order, paid social's weakness would hide in a metric
nobody looks at. I can compute both; I chose the one that keeps acquisition
honest."

### SQL technique

**8. How does the funnel query work on a raw event log?**
"Conditional aggregation: `GROUP BY session_id` with
`MAX(CASE WHEN event_name='add_to_cart' THEN 1 ELSE 0 END)` per stage —
collapsing the log to one row per session with reached-stage flags, then
aggregating flags. It's one pass, index-friendly, and slices cleanly by
month/platform/channel after a join to the customer dim."

**9. How did you compute is_first_order without a flag column?**
"`ROW_NUMBER() OVER (PARTITION BY customer_id ORDER BY order_ts, order_id) = 1`
on delivered orders. The order_id tiebreaker makes it deterministic if two
orders share a timestamp."

**10. NTILE for RFM: what's the catch?**
"Two catches. Quintiles are *relative* — my '5' is top-20% of this base, not
an absolute standard, so segment sizes are stable by construction even when
the base degrades. And ties at bucket boundaries are split arbitrarily; with
heavily-tied F values (many 1-order customers) the F1/F2 boundary is fuzzy.
For production I'd consider fixed business thresholds for F and keep NTILE
for M."

**11. Why did cohort retention use DATEDIFF(MONTH) instead of 30-day windows?**
"Calendar months match how the business reads dashboards and how finance
closes books. The cost: a customer who signs up Jan 31 gets a 1-day M0. With
more time I'd run both; day-exact windows (30/60/90) are better for
experiment readouts, calendar months for reporting."

**12. Most complex query in the repo?**
"Either the cohort triangle — conditional aggregation over cohort × offset
with right-censoring so young cohorts show NULL, never a fake 0 — or the
store-flywheel query in module 17 joining each store-month's on-time rate to
its customers' next-month repeat rate, which needed a LEFT JOIN against a
distinct customer-month spine because SQL Server won't allow EXISTS inside an
aggregate."

### Judgment & product sense

**13. Your biggest insight — why should ops believe the causality?**
"Three converging pieces of evidence, not one: (i) within the same period,
bad-first customers churn +17 pp vs good-first; (ii) the *zones* that
degraded show the same pattern amplified after May while other zones are
flat — a natural experiment; (iii) the funnel shows cart→checkout dropping
only in those zones, which is the availability mechanism, not just
correlation with unhappy raters. To be rigorous I'd still want an experiment
— e.g., priority-fulfilment for a random half of first orders — and that's
exactly the kind of test my A/B testing project covers."

**14. The May promo added ₹55L GMV. The CMO calls it a success. Push back.**
"Volume yes, customers no. 48% of the May cohort is discount-led and retains
at 21% M1 vs 55% for the full-price half; June gave back ₹14L; discount cost
hit 9.1% of GMV; and payback math says those users never clear even referral
CAC. My counter isn't 'no promos' — it's laddered offers on orders 2-3,
promo-per-retained-customer as the success metric, and capacity-gating so the
spike doesn't break stores like Whitefield again."

**15. If you could only track 3 metrics for this business?**
"Perfect-order rate (supply promise kept), M1 cohort retention (does the
product form a habit), and contribution per order (can the habit pay for
itself). GMV is a lagging output of those three."

**16. What would you A/B test first, and how?**
"The laddered promo vs blanket discount, randomized at customer level on new
signups, primary metric M1 retention, guardrails on activation rate and
week-1 orders; power the test off the observed 34→55% retention spread. The
experimental design details — sample size, z-test for proportions, guardrail
analysis — are the core of my separate promotion-framing A/B project, so the
two projects deliberately cover complementary skills."

**17. Estimate the annual value of fixing the two stressed stores.**
"Directionally: the zones hold ~28% of customers; their post-May churn runs
+13 pp above baseline. On ~6,600 monthly actives that's roughly 240 extra
customers lost per month × ~₹440 contribution over 90 days ≈ ₹1 Cr-scale
annualized damage before counting the cart→checkout conversion loss — so a
capacity fix costing less than that pays for itself. I'd tighten this with
zone-level LTV instead of the blended figure."

### Cross-examination / stress test

**18. Where would this analysis break on real data?**
"Event loss and identity: real logs drop events, sessions fragment, guests
convert to accounts — my session→order join is too clean. Real promises vary
per order (surge, weather), so my on-time flag would need the *actual quoted*
promise per order. Cancellations mix payment failure with stock-outs and need
a reason code. And real margins move with procurement prices; mine are static
per SKU."

**19. Anything in the data that surprised you?**
"Ratings under-predict behaviour: after a 1-2★ order, customers still reorder
within 30 days ~79% of the time vs ~86% after 5★ — the habit forgives one bad
order. It's the *first* order and *repeated* zone failures that kill
retention. That changed my recommendation from 'chase ratings' to 'guard the
first order and fix systemic zone failures'."

**20. Why SQL Server / T-SQL and not pandas for the analysis?**
"Scale and hand-off realism: the analysis layer lives where the data lives,
runs on 2.4M rows without moving them, and every module is a reviewable,
re-runnable artifact a team could schedule. Python's role is the data
generator (and an optional loader). Also, analyst interviews test SQL — this
repo *is* my SQL portfolio."

**21. What's deliberately out of scope?**
"Three things, each covered elsewhere or noted: experimentation (separate A/B
project), ML models (health score is a transparent heuristic by design — I'd
reach for a logistic churn model only after the heuristic stops being enough),
and data cleaning (the generator emits clean data; module 03 covers integrity
checks, not messiness)."

**22. If Eternal gave you this exact role tomorrow, week-1 plan?**
"Days 1-2: metric definitions and lineage — where GMV, on-time, retention
come from and who owns them. Days 3-4: rebuild my six-KPI monthly view on
real data to find where reality diverges from my priors (funnel conversion,
AOV, M1). Day 5: one deep-dive the team already suspects — my bet is
first-order experience — and end the week with one chart, one number, one
recommendation, exactly like this project's insight format."
