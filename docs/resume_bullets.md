# Resume Bullets

Three formats — pick per resume space. Numbers are from this dataset and
reproducible; keep them only if you can defend them (see interview_qa.md).

**Honesty rule:** the project title carries "simulated / Blinkit-style" once,
visibly. After that the bullets can talk pure analytics. Never imply
employment at or data from a real company — interviewers at Eternal/Zomato
WILL ask where the data came from, and "I engineered the dataset myself with
known ground-truth patterns, then recovered them in SQL" is a *stronger*
answer than a vague Kaggle CSV.

---

## A. Compact (2 lines, one-page resume)

> **Quick-Commerce Product Analytics (Blinkit-style simulation)** — SQL Server, Power BI, Python
> Built a 12-month, 161K-order marketplace dataset and a 10-module T-SQL analysis suite (funnels, cohorts, RFM, GMV decomposition, CAC payback); surfaced 6 growth insights — incl. bad first deliveries raising churn +17 pp and a promo cohort retaining 21% vs 55% — into a 5-page Power BI executive dashboard.

## B. Standard (3-4 bullets)

**Product Growth & Marketplace Health Analytics — QuickKart (simulated Blinkit-style platform)**
*T-SQL (SQL Server), Power BI, Python (NumPy/pandas) · [GitHub link]*

- Modeled a quick-commerce star schema (8 tables, 2.4M rows: orders, baskets, app-event funnel logs, marketing spend) and wrote **20+ production-style T-SQL analyses** using window functions, cohort logic, and conditional aggregation across 10 modules.
- Quantified an **activation cliff**: customers whose first order arrived late/incomplete repeated at 44% vs 72% within 28 days and churned +17 pp — proposed a first-order SLA projected to save ~550 repeat customers/year.
- Decomposed MoM GMV into actives × frequency × AOV, exposing that a **May promo spike (+₹55L GMV) was 86% one-off actives** with the discount-led half of the cohort retaining at 21% vs 55% — recommended laddered retention offers over blanket discounts.
- Built channel **CAC-payback and RFM/health-score frameworks** (Champions = 24% of buyers, 61% of spend) and shipped a 5-page Power BI dashboard (cohort matrix, store-ops scorecard, funnel) on a documented star-schema model with 25+ DAX measures.

## C. Detailed (project section of a longer CV / portfolio page)

Use B, plus:

- Engineered the dataset generator itself (seeded NumPy simulation with injected causal patterns — channel quality gaps, store capacity stress, tenure-driven margin expansion) so every insight has verifiable ground truth; documented 25+ metric definitions with formulas and caveats.
- Diagnosed a marketplace ops failure: two dark stores' on-time rate collapsed 74% → 31% post-May, cutting cart→checkout conversion −5 pp and raising zone churn +13 pp — connected ops SLAs to demand-side funnel and retention metrics.

---

## Skills line these bullets justify

`SQL (T-SQL: window functions, CTEs, cohort analysis) · Power BI (DAX, star schema) · Python (pandas, NumPy) · Product metrics (AARRR, HEART, retention cohorts, funnel, CAC/LTV, RFM) · Experiment-adjacent judgment (promo evaluation, driver decomposition)`

## Talking-point map (bullet → where the proof lives)

| Claim | Proof |
|---|---|
| +17 pp churn from bad first order | `sql/14_churn.sql` B · insights §1 |
| 44% vs 72% repeat-28d | ground truth + module 14 logic |
| May promo 21% vs 55% M1 | `sql/13_retention_cohorts.sql` D |
| GMV bridge 86% actives | `sql/16_gmv_decomposition.sql` B (47.9/55.4) |
| Champions 24% → 61% of spend | `sql/15_rfm_segmentation.sql` B |
| On-time 74% → 31% | `sql/17_marketplace_health.sql` B |
| 25+ DAX measures | `powerbi/model_and_measures.md` |
