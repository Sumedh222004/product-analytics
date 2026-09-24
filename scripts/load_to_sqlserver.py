"""
Alternative loader: CSVs -> SQL Server via pyodbc (no BULK INSERT permission
needed). Use this if sql/02_load_data.sql fails on your machine.

    pip install pyodbc pandas
    python scripts/load_to_sqlserver.py --server localhost

Assumes 00 + 01 have been run (database + tables exist). Loads in FK-safe
order and reports row counts. ~2-4 minutes for the full dataset.
"""

import argparse
import time
from pathlib import Path

import pandas as pd

try:
    import pyodbc
except ImportError:
    raise SystemExit("pyodbc missing:  pip install pyodbc")

DATA = Path(__file__).resolve().parents[1] / "data" / "output"

# (csv, table, columns) in FK-safe load order
TABLES = [
    ("stores.csv", "dbo.dim_store",
     ["store_id", "store_code", "zone_name", "city", "launch_date", "base_promise_min"]),
    ("products.csv", "dbo.dim_product",
     ["product_id", "product_name", "category", "unit_price", "unit_cost", "is_private_label"]),
    ("customers.csv", "dbo.dim_customer",
     ["customer_id", "signup_ts", "acquisition_channel", "platform", "home_store_id"]),
    ("orders.csv", "dbo.fact_orders",
     ["order_id", "customer_id", "store_id", "order_ts", "status", "promised_min",
      "actual_delivery_min", "item_total", "discount_amount", "delivery_fee",
      "handling_fee", "net_amount", "payment_method", "rating", "items_missing"]),
    ("order_items.csv", "dbo.fact_order_items",
     ["order_id", "product_id", "quantity", "unit_price", "line_amount"]),
    ("app_events.csv", "dbo.fact_app_events",
     ["session_id", "customer_id", "event_name", "event_ts", "platform", "order_id"]),
    ("marketing_spend.csv", "dbo.fact_marketing_spend",
     ["month_start", "channel", "spend_inr"]),
]

CLEAR_ORDER = ["dbo.fact_app_events", "dbo.fact_order_items", "dbo.fact_orders",
               "dbo.fact_marketing_spend", "dbo.dim_customer", "dbo.dim_product",
               "dbo.dim_store"]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--server", default="localhost")
    ap.add_argument("--database", default="quickkart_analytics")
    ap.add_argument("--driver", default="ODBC Driver 17 for SQL Server")
    ap.add_argument("--user", help="SQL login (omit for Windows auth)")
    ap.add_argument("--password")
    ap.add_argument("--chunk", type=int, default=50_000)
    args = ap.parse_args()

    # TrustServerCertificate=yes: ODBC Driver 18 encrypts by default and rejects
    # the local instance's self-signed cert without it (fine for localhost).
    if args.user:
        conn_str = (f"DRIVER={{{args.driver}}};SERVER={args.server};"
                    f"DATABASE={args.database};UID={args.user};PWD={args.password};"
                    f"TrustServerCertificate=yes")
    else:
        conn_str = (f"DRIVER={{{args.driver}}};SERVER={args.server};"
                    f"DATABASE={args.database};Trusted_Connection=yes;"
                    f"TrustServerCertificate=yes")

    cn = pyodbc.connect(conn_str, autocommit=False)
    cur = cn.cursor()
    cur.fast_executemany = True

    print("clearing tables (FK-safe order) ...")
    for t in CLEAR_ORDER:
        cur.execute(f"DELETE FROM {t}")
    cn.commit()

    for csv_name, table, cols in TABLES:
        path = DATA / csv_name
        if not path.exists():
            raise SystemExit(f"{path} not found — run data/generate_data.py first")
        t0 = time.time()
        df = pd.read_csv(path)
        df = df[cols]                             # enforce column order
        df = df.astype(object).where(pd.notna(df), None)   # NaN -> NULL

        placeholders = ",".join("?" * len(cols))
        sql = f"INSERT INTO {table} ({','.join(cols)}) VALUES ({placeholders})"

        rows = df.values.tolist()
        for i in range(0, len(rows), args.chunk):
            cur.executemany(sql, rows[i:i + args.chunk])
            cn.commit()
        print(f"  {table:<28} {len(rows):>9,} rows  ({time.time() - t0:,.1f}s)")

    cur.execute("SELECT COUNT(*) FROM dbo.fact_orders")
    print(f"done. fact_orders now holds {cur.fetchone()[0]:,} rows.")
    cn.close()


if __name__ == "__main__":
    main()
