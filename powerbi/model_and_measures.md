# Power BI — Data Model & DAX Measures

Import the nine `vw_pbi_*` views (never raw tables). This file defines the
relationships and every measure, ready to paste.

## 1. Data model (star schema)

```
                    vw_pbi_dim_date (mark as Date table, key: date_key)
                          ▲ 1
                          │
                          │ *  (order_date)
vw_pbi_dim_customer 1───* vw_pbi_fact_orders *───1 vw_pbi_dim_store
        (customer_id)                              (store_id)
                          │ *
                          │  (product joins live in SQL — the fact carries
                          ▼   item_margin/contribution, so no bridge needed)

Month-grain tables (relate their month column to dim_date[date_key],
cross-filter single, and slice them by the SAME date slicer):
  vw_pbi_funnel_monthly[session_month]      → dim_date[date_key]
  vw_pbi_store_month_ops[order_month]       → dim_date[date_key]
  vw_pbi_marketing[month_start]             → dim_date[date_key]
  vw_pbi_cohort_retention[cohort_month]     → dim_date[date_key]
  vw_pbi_dim_product: disconnected (used by its own visuals on page 5)
```

Relationship settings: all many-to-one, single direction, from fact → dim.
Mark `vw_pbi_dim_date` as the model's Date table (Table tools → Mark as date
table → `date_key`), otherwise the time-intelligence measures below break.

Rename tables in the model for clean visuals: `Orders`, `Customers`, `Stores`,
`Dates`, `Funnel`, `StoreOps`, `Marketing`, `CohortRetention`, `Products`.
The DAX below uses these friendly names.

## 2. Core measures (create in Orders table)

```dax
Delivered Orders =
CALCULATE ( COUNTROWS ( Orders ), Orders[status] = "delivered" )

GMV =
CALCULATE ( SUM ( Orders[item_total] ), Orders[status] = "delivered" )

Net Revenue =
CALCULATE ( SUM ( Orders[net_amount] ), Orders[status] = "delivered" )

Discounts = 
CALCULATE ( SUM ( Orders[discount_amount] ), Orders[status] = "delivered" )

Discount Rate % =
DIVIDE ( [Discounts], [GMV] )

AOV =
DIVIDE ( [GMV], [Delivered Orders] )

Active Customers =
CALCULATE ( DISTINCTCOUNT ( Orders[customer_id] ), Orders[status] = "delivered" )

Orders per Active =
DIVIDE ( [Delivered Orders], [Active Customers] )

Contribution =
CALCULATE ( SUM ( Orders[contribution_rs] ), Orders[status] = "delivered" )

Contribution per Order =
DIVIDE ( [Contribution], [Delivered Orders] )

Item Margin % =
DIVIDE (
    CALCULATE ( SUM ( Orders[item_margin] ), Orders[status] = "delivered" ),
    [GMV]
)
```

## 3. Growth / time intelligence

```dax
GMV PM =
CALCULATE ( [GMV], DATEADD ( Dates[date_key], -1, MONTH ) )

GMV MoM % =
DIVIDE ( [GMV] - [GMV PM], [GMV PM] )

Active Customers PM =
CALCULATE ( [Active Customers], DATEADD ( Dates[date_key], -1, MONTH ) )

New Customers =
CALCULATE (
    COUNTROWS ( Customers ),
    USERELATIONSHIP ( Customers[signup_date], Dates[date_key] )
)
-- create the inactive relationship Customers[signup_date] → Dates[date_key]
-- (fact-to-date stays the active one)
```

## 4. Operations / experience

```dax
On-Time % =
DIVIDE (
    CALCULATE ( SUM ( Orders[is_on_time] ), Orders[status] = "delivered" ),
    [Delivered Orders]
)

Perfect Order % =
DIVIDE (
    CALCULATE ( SUM ( Orders[is_perfect_order] ), Orders[status] = "delivered" ),
    [Delivered Orders]
)

Late 5+ min % =
DIVIDE (
    CALCULATE ( SUM ( Orders[is_late_5plus] ), Orders[status] = "delivered" ),
    [Delivered Orders]
)

Avg Delivery Min =
CALCULATE ( AVERAGE ( Orders[actual_delivery_min] ), Orders[status] = "delivered" )

Cancellation % =
DIVIDE (
    CALCULATE ( COUNTROWS ( Orders ), Orders[status] = "cancelled" ),
    COUNTROWS ( Orders )
)

Avg Rating =
CALCULATE ( AVERAGE ( Orders[rating] ), Orders[status] = "delivered" )
```

## 5. Funnel (Funnel table)

```dax
Sessions = SUM ( Funnel[sessions] )
Converted Sessions = SUM ( Funnel[converted] )
Session Conversion % = DIVIDE ( [Converted Sessions], [Sessions] )
Cart Reach % = DIVIDE ( SUM ( Funnel[reached_cart] ), [Sessions] )
Cart to Checkout % =
DIVIDE ( SUM ( Funnel[reached_checkout] ), SUM ( Funnel[reached_cart] ) )
```

## 6. Acquisition (Marketing table)

```dax
Marketing Spend = SUM ( Marketing[spend_inr] )
Signups = SUM ( Marketing[signups] )
Activated Signups = SUM ( Marketing[activated_7d] )
CAC = DIVIDE ( [Marketing Spend], [Signups] )
CAC per Activated = DIVIDE ( [Marketing Spend], [Activated Signups] )
Activation % = DIVIDE ( [Activated Signups], [Signups] )
```

## 7. Retention (CohortRetention table)

```dax
Cohort Size = MAX ( CohortRetention[cohort_size] )
Cohort Actives = SUM ( CohortRetention[active_customers] )
Retention % = DIVIDE ( [Cohort Actives], [Cohort Size] )
```

Cohort matrix visual: Rows = `cohort_month`, Columns = `month_offset`,
Values = `Retention %`, with a diverging color scale (Format → Cell elements
→ Background color). This is the classic retention triangle.

## 8. Formatting conventions

* Currency: `₹#,##0` (GMV, AOV, CAC, Contribution). Lakh/crore display:
  Format → Display units.
* Percentages: 1 decimal.
* KPI cards: current month vs `PM` measure in the tooltip.
* Consistent semantic colors: green = healthy/on-time, amber = watch,
  red = at-risk/late. Don't rely on color alone — keep data labels on.
