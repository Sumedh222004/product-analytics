# Metric Definitions

Every metric in this project, precisely defined. In interviews, most follow-up
questions are really definition questions — know the formula, the why, and the
caveat for each.

## Conventions

- **Delivered orders only** for all demand metrics (GMV, AOV, retention, RFM).
  Cancelled orders appear only in ops metrics (cancellation rate).
- Money = whole rupees. Month = calendar month. As-of date = 2026-08-31.

## Acquisition & activation

| Metric | Definition | Why / caveat |
|---|---|---|
| New customers | count of signups in the month | vanity on its own — always pair with activation |
| CAC | channel marketing spend ÷ signups | ignores signup quality |
| CAC per activated | spend ÷ customers with a delivered order ≤7d of signup | the honest CAC; can be ~1.5x raw CAC for weak channels |
| Activation rate | % of signups with first delivered order within 7 days | 7d chosen because 79% of eventual first orders happen within 1 day — beyond a week the habit window has closed |
| Time to first order | signup → first delivered order | distribution, not average — it's heavily right-skewed |
| CAC payback month | first tenure month where cumulative contribution per signup ≥ CAC | contribution, not GMV; sequential monthly accrual |

## Engagement & conversion

| Metric | Definition | Why / caveat |
|---|---|---|
| Session | one `session_id` in the event log (one app visit) | logged-in sessions only in this dataset |
| Funnel stage reach | session has ≥1 event of that stage (`MAX(CASE…)` per session) | order within a session, stages assumed monotonic |
| Session conversion | sessions with `payment_success` ÷ all sessions | includes later-cancelled orders (payment happened) |
| Step conversion | stage N reach ÷ stage N-1 reach | localizes the leak; %-of-sessions view hides it |
| Search vs browse | sessions containing a `search` event vs not | proxy for intent, not causality — searchers self-select |

## Retention & lifecycle

| Metric | Definition | Why / caveat |
|---|---|---|
| Cohort | signup calendar month | signup, not first-order, so M0 also reflects activation |
| Mk retention | % of cohort with ≥1 delivered order k calendar months after cohort month | calendar-month offset (DATEDIFF month), not 30-day windows; right-censored cohorts show NULL |
| Churned | no delivered order in the 56 days before as-of | ~2x the median inter-order gap; 28d would over-flag |
| At risk | last order 29-56 days ago | the actionable CRM window |
| Reactivation | a >56-day gap between consecutive orders, then a return | proves win-back is possible; sizes the opportunity |
| Bad first experience | first delivered order >5 min late OR items missing | the project's key churn driver flag |

## Revenue & economics

| Metric | Definition | Why / caveat |
|---|---|---|
| GMV | Σ item_total (pre-discount basket value), delivered | industry convention; includes what discounts give away |
| Net revenue | Σ (item_total − discount + delivery fee + handling fee) | what the platform actually bills |
| AOV | GMV ÷ delivered orders | rises with tenure mix — check mix before celebrating |
| Item margin | Σ (line_amount − qty × unit_cost) | product-level economics from the basket |
| Contribution / order | item margin + fees − discount − ₹30 last-mile cost | the ₹30 is an assumption (documented, sensitivity-testable); no rider-cost data in this dataset |
| Discount rate | discounts ÷ GMV | promo intensity; May 2026 = 9.1% vs ~1.5% baseline |
| GMV decomposition | GMV ≡ actives × orders/active × AOV; MoM change split by sequential substitution | split is exact but order-dependent — state the substitution order |
| Growth accounting | month GMV from new / retained (active prev month) / reactivated | shows growth *quality*, not just growth |

## Marketplace / ops

| Metric | Definition | Why / caveat |
|---|---|---|
| On-time % | actual ≤ promised minutes | promise varies by store & peak — it's a kept-promise rate, not a speed rate |
| Late 5+ % | actual > promised + 5 | the experience-destroying tail, tracks ratings much better than average delay |
| Items missing % | delivered orders flagged incomplete | availability/picking failure |
| Perfect order rate | on-time AND complete (delivered) | the ops north star; single number an exec can track |
| Cancellation rate | cancelled ÷ all placed orders | supply failure + payment issues mixed |

## Experience (HEART)

| Letter | Metric here |
|---|---|
| Happiness | avg order rating; % rated ≥4 (rating response ~52%, skews to unhappy — treat levels with care, trust *trends*) |
| Engagement | orders per active; sessions per user |
| Adoption | activation rate of the month's signups |
| Retention | M1 of the previous month's cohort |
| Task success | session conversion; perfect order rate |

## Segmentation & scores

| Metric | Definition | Why / caveat |
|---|---|---|
| RFM scores | NTILE(5) on recency (reversed), frequency, monetary | quintiles are relative to this base, not absolute standards |
| RFM segment | rule map on (R,F), M as context (see module 15) | names are conventions; the action table is what matters |
| Customer health score | 0-100: Recency 30 + Frequency(56d) 25 + Monetary(56d) 20 + Experience(90d perfect-order rate) 15 + Trend(28v28) 10 | weights are a judgment call — defend the ordering (recency > frequency > money), not the exact numbers |
| Product health score | 0-100: velocity 25 + GMV 20 + margin% 20 + buyer reach 20 + weekly consistency 15 (56-day window) | quintile-based → relative; a "Review" SKU in a small category may still be strategic (e.g., baby care basket anchor) |
