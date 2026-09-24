# Study Guide — own this project in 5 days

The project is only worth resume space if you can rebuild any piece of it on
a whiteboard. This plan gets you there in ~2-3 hours/day.

## Day 1 — Run it end to end (hands on keyboard)

1. `pip install -r requirements.txt`, then `python data/generate_data.py` (~1 min).
2. Read the generator's docstring — memorize the six injected scenarios (S1-S6).
   You must be able to say "the data has known ground truth" and list them.
3. Run `sql/00 → 04` in SSMS. Every row of the 03 audit should say PASS —
   understand what each check protects against.
4. Skim the three base views in 04 until you can explain *why* they exist
   (single source of truth for flags/definitions; every module reuses them).

**Checkpoint:** explain to a friend how data flows: Python → CSV → BULK INSERT
→ star schema → views → analysis → Power BI.

## Day 2 — Demand side (modules 10-13)

- Run each module, query by query. For every result set, write ONE sentence
  of interpretation in your own words before reading the file's comments.
- Rebuild from scratch, in a blank window, without looking:
  1. activation rate by channel (joins + CASE),
  2. the funnel conditional aggregation (`MAX(CASE WHEN ...)`) — this is the
     single most-asked SQL pattern in analyst interviews,
  3. a minimal cohort: cohort_month × month_offset × count.
- Memorize: M1 42.8 / M3 27.3 / M6 22.4; referral 55.6 vs influencer 30.4;
  funnel 100 → 75.7 → 55.5 → 46.2 → 41.0.

## Day 3 — Money and churn (modules 14-16)

- Re-derive the GMV bridge algebra on paper: prove the three terms telescope
  to ΔGMV (interview_qa Q3 depends on this).
- Rebuild: `ROW_NUMBER` first-order flag; LAG-based reorder gap; NTILE RFM
  scores.
- Memorize: bad first order → repeat-28d 72.5 vs 43.9, churn 67.0 vs 83.5;
  May cohort discount-led 20.8 vs full-price 54.6; margin/order ₹151 → ₹224.

## Day 4 — Ops, HEART, scores (17-19) + Power BI build

- Modules 17-19: focus on the *design decisions* — why 56-day windows, why
  those score weights, why perfect-order rate is the ops north star.
- Build the Power BI dashboard from `powerbi/build_guide.md` (2-3 h). Screenshot
  pages 1 and 3 into `docs/img/` and link them in the README.
- Publish to Power BI Service if you want a live link on the resume.

## Day 5 — Narrative and defense

- Read `docs/insights_report.md` twice; practice the 90-second walkthrough
  (interview_qa Q1) out loud until it's smooth.
- Do all 22 Q&A as a self-mock: read the question, answer OUT LOUD, then
  compare. Flag the ones you fumbled; redo tomorrow.
- Prepare your "honesty paragraph": data is simulated, seeded, with injected
  ground truth — and why that made the analysis *more* rigorous, not less.

## Retention drills (repeat weekly)

- Whiteboard in <5 min each: funnel query · cohort query · RFM scoring ·
  first-order flag · GMV bridge terms.
- One number per module, no notes: 10→₹600 (influencer CAC/activated),
  11→57% same-day first orders, 12→56.6% search conversion, 13→20.8% May
  discount-led M1, 14→+16.5 pp churn, 15→Champions 24%/61%, 16→₹48L of May's
  ₹55L from actives, 17→30.6% on-time, 18→~79% reorder after 1-2★, 19→Healthy
  15.1% hold 67% of spend.

## Explaining "why these tools"

- **T-SQL**: analysis lives where data lives; window functions do the heavy
  lifting; each module is a re-runnable artifact.
- **Power BI**: the standard India-analytics stack next to SQL Server; the
  model layer (star schema + DAX) is a skill in itself.
- **Python**: only for data engineering (generation/loading) — deliberate
  scope discipline; the analysis is SQL-first because the target role is.
