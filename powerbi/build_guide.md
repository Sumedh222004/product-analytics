# Power BI — Step-by-Step Dashboard Build Guide

Target: a 5-page dashboard you can build in ~2-3 hours and screenshot for the
README/resume. Prereqs: Power BI Desktop (free), SQL scripts 00-20 executed.

---

## Step 0 — Connect & import (15 min)

1. Power BI Desktop → **Get Data → SQL Server**.
   Server: `localhost` (or your instance name), Database: `quickkart_analytics`,
   Connectivity: **Import**.
2. Select ONLY the nine `vw_pbi_*` views. Load.
3. Rename tables: `Orders`, `Customers`, `Stores`, `Dates`, `Funnel`,
   `StoreOps`, `Marketing`, `CohortRetention`, `Products`.
4. Model view: create the relationships listed in `model_and_measures.md`,
   mark `Dates` as the date table, set all relationships single-direction.
5. Create every measure from `model_and_measures.md` (a `_Measures` display
   folder keeps them tidy).

Global elements on every page: a **month-range slicer** (`Dates[month_start]`,
"Between" style) across the top, and slicers for `Stores[zone_name]`,
`Customers[acquisition_channel]`, `Customers[platform]` where noted.

---

## Page 1 — Executive Overview

| # | Visual | Fields / measure | Notes |
|---|--------|------------------|-------|
| 1 | 6 KPI cards | `GMV`, `Delivered Orders`, `Active Customers`, `AOV`, `Perfect Order %`, `Avg Rating` | add `GMV MoM %` to GMV tooltip |
| 2 | Line + column combo | X: `Dates[month_start]`; Columns: `GMV`; Line: `Active Customers` | the growth headline |
| 3 | Stacked column | X: month; Y: GMV; Legend: `Stores[zone_name]` | Whitefield/Marathahalli flatten after May |
| 4 | Line | X: month; Y: `Perfect Order %` | annotate the May inflection (Insert → Text box) |
| 5 | Card + line | `Session Conversion %` by month (Funnel table) | demand quality at a glance |

Layout tip: KPI row on top, growth chart left-half, ops lines right-half.

## Page 2 — Growth, Acquisition & Funnel

| # | Visual | Fields | Notes |
|---|--------|--------|-------|
| 1 | Funnel visual | Values: `Sessions`, `SUM(reached_product_view)`, `SUM(reached_cart)`, `SUM(reached_checkout)`, `Converted Sessions` | overall conversion story |
| 2 | Clustered column | X: `Marketing[channel]`; Y: `CAC`, `CAC per Activated` | the "CAC lies without activation" chart |
| 3 | Scatter | X: `CAC`; Y: `Activation %`; Size: `Signups`; Legend: channel | quadrant read: bottom-right = burn |
| 4 | Line | X: month; Y: `Session Conversion %`; Legend: `Funnel[platform]` | android vs ios gap |
| 5 | Column | X: month; Y: `Signups`; Legend: channel (stacked) | May promo spike visible |

## Page 3 — Retention & Cohorts

| # | Visual | Fields | Notes |
|---|--------|--------|-------|
| 1 | Matrix | Rows: `CohortRetention[cohort_month]`; Columns: `[month_offset]`; Values: `Retention %` | background color scale (red→green); THE screenshot |
| 2 | Line | X: `month_offset`; Y: `Retention %`; Legend: cohort_month (filter to Feb-May 2026) | May-2026 curve sits below |
| 3 | Clustered bar | Y: `Customers[acquisition_channel]`; X: M1 retention — use `Retention %` with a visual-level filter `month_offset = 1`, via a `Customers`→cohort slicer, or import module 13.C's numbers as a small table | channel quality |
| 4 | Card row | blended M1 / M3 / M6 (visual filters on `month_offset`) | |

## Page 4 — Marketplace & Ops Health (StoreOps table)

| # | Visual | Fields | Notes |
|---|--------|--------|-------|
| 1 | Matrix | Rows: `zone_name`; Columns: `order_month`; Values: `on_time_pct` | conditional format: <50 red |
| 2 | Line | X: `order_month`; Y: `avg_delivery_min`; Legend: `zone_name` | two lines break away in May |
| 3 | Line | X: `order_month`; Y: `avg_rating`; Legend: `zone_name` | ratings follow ops with a lag |
| 4 | Clustered column | X: `zone_name`; Y: `cancel_pct`, `items_missing_pct` (post-May filter) | |
| 5 | Heatmap matrix | Rows: `Dates[day_name]`; Columns: hour — add `HOUR = HOUR(Orders[order_date]...)`? Use module 17.C's output imported as a table, or a calculated column on a datetime if you kept one | staffing story; optional |

## Page 5 — Segments, Health & Monetization

| # | Visual | Fields | Notes |
|---|--------|--------|-------|
| 1 | Treemap | Group: `Customers[rfm_segment]`; Values: `Net Revenue` | value concentration |
| 2 | Stacked bar (100%) | Y: `Stores[zone_name]`; Legend: `Customers[customer_health_tier]`; Values: count of customers | stressed zones skew red |
| 3 | Column | X: tenure bucket (import module 16.D2 output as a table, or bucket in DAX) ; Y: `Contribution per Order` | the monetization slide |
| 4 | Table | `Products[product_name]`, `category`, `product_health_score`, `product_health_tier` | sort ascending = review list |
| 5 | Donut | `Customers[customer_health_tier]` by count | with % labels |

---

## Finishing touches

* **Theme**: View → Themes → pick one; then keep semantic colors consistent
  (green = healthy, red = at-risk) across pages.
* **Titles as sentences**: "GMV grew 9% MoM, led by order frequency" beats
  "GMV by month". Write the insight into each title — interviewers notice.
* **Bookmark** a "May 2026 story" view: filters set to the stressed zones,
  months Apr-Aug.
* **Export screenshots** of pages 1 and 3 into `docs/img/` and link them in
  the README.
* Optional publish: Power BI Service (free account) → Publish → get a share
  link for the resume. The dataset is synthetic, so nothing confidential.

## Troubleshooting

* Retention % shows > 100% → relationship from CohortRetention to Dates is
  missing/bidirectional; keep it single-direction, or slice by
  `CohortRetention[cohort_month]` directly.
* Time intelligence blank → `Dates` not marked as date table.
* Import slow → you imported raw tables; use only the `vw_pbi_*` views.
