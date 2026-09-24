# VERIFICATION.md — prove every layer works, step by step

Work through the 8 stages in order. Each stage has a **gate**: exact numbers
your machine must show before moving on (the dataset is seeded, so almost
everything matches to the digit). If a gate fails, use the troubleshooting
under it — or stop and debug there; later stages can't work if an earlier one
is broken.

Numbers marked **≈** are the only ones allowed small wiggle (rounding /
hour-truncation at bucket edges). Everything else is exact.

---

## Stage 0 — One-time setup

| Install | Where | Notes |
|---|---|---|
| Python 3.10+ | python.org | tick **"Add python.exe to PATH"** during install |
| SQL Server 2019+ **Developer** edition (free) | Microsoft "SQL Server downloads" | "Basic" install type is fine; default instance; Windows Authentication |
| SSMS (SQL Server Management Studio) | separate free download | connects with Server name `localhost`, Windows Auth |
| Power BI Desktop (free) | Microsoft Store | needed only for Stage 8 |

**Where to unzip the repo matters:** put it at a short local path like
`C:\projects\blinkit-product-analytics`. **Not** Desktop/Documents if OneDrive
syncs them — the SQL Server *service* must be able to read the CSV files, and
synced/cloud folders regularly break BULK INSERT with "Access is denied".

---

## Stage 1 — Data generator

```bat
cd C:\projects\blinkit-product-analytics
pip install -r requirements.txt
python data\generate_data.py
```

Runs in roughly 10–60 s. **Gate — the summary must read exactly:**

```
customers        :    23,670
products         :       406
orders           :   166,080  (delivered 161,302)
order_items      :   750,065
app_events       : 1,450,578
GMV (delivered)  : Rs  114,712,645
AOV (delivered)  : Rs    711
```

and `data\output\` must contain 7 CSVs (~99 MB total):
`app_events.csv` ~72 MB · `order_items.csv` ~14 MB · `orders.csv` ~12 MB ·
`customers.csv` ~1.1 MB · `products.csv` / `stores.csv` / `marketing_spend.csv` small.

**If the numbers differ:** your NumPy is outside the pinned range. Run
`pip show numpy` — it must be 2.x. Fix with
`pip install --force-reinstall "numpy>=2,<3" "pandas>=2"` and regenerate.
(Different numbers aren't "wrong" data — but then they won't match the docs,
and matching is the whole point of verification.)

---

## Stage 2 — Database & schema (scripts 00, 01)

In SSMS: File → Open → `sql\00_create_database.sql` → **Execute (F5)**.
Gate: message `Database quickkart_analytics ready.`

Open and execute `sql\01_create_tables.sql`.
Gate: `Star schema created. dim_date populated: 426 days.`

Object Explorer → refresh → `quickkart_analytics` → Tables shows **8 tables**
(`dim_customer, dim_date, dim_product, dim_store, fact_app_events,
fact_marketing_spend, fact_order_items, fact_orders`).

Re-run rule: 01 drops and recreates everything — if you ever re-run it, you
must redo Stages 3–4 as well.

---

## Stage 3 — Load the CSVs (script 02) — *where most first-run failures live*

1. Open `sql\02_load_data.sql`.
2. **Query menu → SQLCMD Mode** — must be ticked (the `:setvar` line turns grey/highlighted).
3. Edit the path line to your real path, keeping the quotes, no trailing `\`:
   `:setvar DataPath "C:\projects\blinkit-product-analytics\data\output"`
4. Execute. Takes ~1–3 min.

**Gate — the final grid must show exactly:**

| table_name | rows_loaded |
|---|---|
| dim_store | 6 |
| dim_product | 406 |
| dim_customer | 23,670 |
| fact_orders | 166,080 |
| fact_order_items | 750,065 |
| fact_app_events | 1,450,578 |
| fact_marketing_spend | 60 |

Any count differing from Stage 1 = partial load → just re-run 02 (it clears
tables first, so re-running is always safe).

**Troubleshooting:**

| Error | Cause → fix |
|---|---|
| `Incorrect syntax near ':'` | SQLCMD Mode is off → Query menu → SQLCMD Mode |
| `Cannot bulk load because the file ... could not be opened. Operating system error 5 (Access is denied)` | SQL Server service can't read your folder → move repo to `C:\projects\`, or Properties → Security → give **NT Service\MSSQLSERVER** read access |
| `...file does not exist` | path typo in `:setvar`, or Stage 1 not run |
| No BULK INSERT permission at all | use the fallback loader: `pip install pyodbc` then `python scripts\load_to_sqlserver.py --server localhost` (add `--driver "ODBC Driver 18 for SQL Server"` if 17 isn't installed); same gate applies |

---

## Stage 4 — Built-in data-quality audit (script 03)

Execute `sql\03_quality_checks_and_indexes.sql`.

**Gate 1:** first grid = **11 rows, every `result` = PASS** (row counts,
duplicate keys, orphan rows, basket totals reconciling to order totals,
net-amount arithmetic, NULL rules, date window, no orders before signup,
ratings validity, event→order mapping, non-negative money).

**Gate 2:** second grid:

| status | orders | avg_basket_rs | gmv_rs |
|---|---|---|---|
| cancelled | 4,778 | ≈711 | (small) |
| delivered | 161,302 | 711 | 114,712,645 |

Any FAIL on checks 3–5 → partial load, re-run Stage 3. FAIL on 7–8 → the CSVs
were edited/regenerated after loading — re-run Stages 1→3.

Run-once rule: 03 also creates indexes and foreign keys. Running it twice
gives *"The operation failed because an index or statistics with name ...
already exists"* — that error only means it already ran; it is not a data
problem.

---

## Stage 5 — Base views + analysis modules (04, then 10–19)

Execute `sql\04_base_views.sql` (gate: `Base views created: ...` message).

Then run the modules **in this order** (some views feed later files):
`10 → 11 → 12 → 13 → 14 → 15 → 16 → 17 → 18 → 19`
(18 needs views created in 12 and 13; 20 in Stage 7 needs 12, 13, 15, 17, 19.)

Each file just needs Open → Execute; every query returns a grid, no red errors.
**Gate — spot-check one result per module:**

| Module | Query | Your grid must show |
|---|---|---|
| 10.B | CAC per activated | referral ₹140 · paid_search ₹374 · paid_social ₹421 · influencer ₹600 · organic NULL |
| 10.D | scorecard M1 % | referral 55.6 · organic 49.0 · paid_search 38.7 · paid_social 34.8 · influencer 30.4 |
| 11.B | time to first order | `1_same_day` ≈47.9% · `7_never` 16.4% (3,892 customers) |
| 11.C | aha moment | activation: reached_cart 86.8% vs bounced 70.4% |
| 12.A | funnel | 404,813 sessions → 75.7 → 55.5 → 46.2 → **41.0%** |
| 12.D | search vs browse | 56.6% vs 30.7%; avg ≈9.5 min to order |
| 12.E | cart→checkout | stressed_zone 84.1 → **78.9** post-May; other zones ~84 flat |
| 13.B | cohort summary | 2026-05-01 flagged PROMO COHORT, m1 = 38.2 |
| 13.D | May split | may discount_led **20.8%** (1,865 cust) vs full_price 54.6% (1,985) |
| 14.B0 | repeat within 28d | good 72.5% vs bad **43.9%** |
| 14.A | lifecycle | active 6,572 (33.2%) · at_risk 2,274 (11.5%) · churned 10,932 (55.3%) |
| 14.B | churn by first exp | 67.0% vs **83.5%** |
| 14.D | reactivation | 2,283 / 15,515 = 14.7% |
| 15.B | RFM summary | Champions 4,726 (23.9%) with 60.7% spend share |
| 16.A | Aug 2026 row | 6,724 actives · 22,921 orders · GMV 17,245,320 · AOV 752 |
| 16.B | GMV bridge | every month's `check_diff` ≈ 0; May from_active_customers ≈ +4,790,000 |
| 16.D2 | margin by tenure | ₹151 → ≈₹152 → ≈₹193 → **₹224** |
| 17.B | store damage | stores 4 & 6: on-time ≈74 → ≈30–31 (delta ≈ −43 pp); other stores ~flat |
| 18 view | Aug row | avg_rating 4.34 · perfect_order 62.4 · orders_per_active 3.41 |
| 18 deep-1 | reorder by rating | 5★ ≈85.7% vs 1★ ≈78.8% |
| 19 | health tiers | Healthy 2,988 (15.1%) with 66.8% of 56-day spend; Critical 57.3% |

Right-censoring sanity in 13.A: the cohort triangle's top-right corner is
NULL, never 0 — young cohorts don't get fake zeros.

---

## Stage 6 — Docs cross-check (the "is the analysis right" gate)

Open `docs/insights_report.md` next to SSMS and confirm your grids reproduce
its headlines: the six executive-summary numbers, the module-14 churn split,
the module-13.D May split, and the module-16 monthly KPI table. Everything is
seeded, so a mismatch means a stage above was skipped — not randomness.

---

## Stage 7 — Power BI feed (script 20)

Execute `sql\20_powerbi_views.sql`. Gate: `Power BI feed views ready (9 views).`
Quick test: `SELECT TOP 10 * FROM dbo.vw_pbi_fact_orders;` returns rows with
`item_margin` populated for delivered orders.

## Stage 8 — Power BI dashboard smoke test

Build per `powerbi/build_guide.md` (import the nine `vw_pbi_*` views, set
relationships, mark the date table, paste measures). Then, with **no filters
applied**, drop these measures on cards — each must show:

| Measure | Expected |
|---|---|
| GMV | **114,712,645** (₹11.47 Cr) |
| Delivered Orders | 161,302 |
| Active Customers | 19,778 |
| Sessions | 404,813 |
| Marketing Spend | 4,737,754 |
| Signups (Customers table rows) | 23,670 |

Visual sanity: cohort matrix M1 column sits in the high-30s to mid-40s with
May-2026 = 38.2; the delivery-time line chart shows Whitefield & Marathahalli
breaking upward from May while the other four zones stay flat. A card showing
a different total = a relationship built in the wrong direction or a missed
`status="delivered"` filter in the measure — recheck against
`powerbi/model_and_measures.md`.

---

## Full-reset procedure

If things get tangled, clean slate in 10 minutes: delete the database in SSMS
(right-click → Delete, tick "Close existing connections") → Stage 1 → 2 → 3 → 4 → 5.

## Still stuck?

Debug with three facts: (1) which stage/gate, (2) the exact error text or the
number you got vs expected, (3) whether Stage 4's audit was all-PASS. That
triple pinpoints ~everything.
