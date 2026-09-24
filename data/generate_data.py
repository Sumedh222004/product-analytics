"""
QuickKart — Quick-Commerce Synthetic Data Generator
====================================================
Generates 12 months (Sep 2025 - Aug 2026) of realistic, fully SIMULATED data for
"QuickKart", a fictional Blinkit-style quick-commerce platform operating 6 dark
stores in Bengaluru. No real company data is used or implied.

Outputs 7 CSVs into ./output/ ready for BULK INSERT into SQL Server:
    customers.csv, stores.csv, products.csv, orders.csv,
    order_items.csv, app_events.csv, marketing_spend.csv

Design philosophy
-----------------
Real product data is never random noise — it has causal structure. This script
injects known, realistic business patterns ("scenarios") into the data so that
the SQL analysis has something true to discover. The scenarios:

  S1. Channel quality gap ....... paid channels bring volume but activate and
                                  retain worse than organic/referral; CAC differs.
  S2. Activation cliff .......... a bad FIRST order (late >5 min or items
                                  missing) sharply raises churn afterwards.
  S3. Store stress .............. from May 2026, 2 stores (Whitefield,
                                  Marathahalli) are under-capacity: delivery
                                  times degrade -> ratings drop -> churn rises.
  S4. May promo cohort .......... a discount-led acquisition spike in May 2026
                                  brings deal-seekers who retain poorly.
  S5. Monetization with tenure .. older customers attach more high-margin
                                  categories (personal care / household), so
                                  contribution margin per order rises with tenure.
  S6. Behavioral texture ........ weekend/evening peaks, seasonality, power-user
                                  frequency distribution (gamma), festive bump.

Everything is seeded (SEED=42) => the dataset is reproducible run-to-run on the
same numpy version. Runtime ~1 min, output ~250 MB of CSV.

Usage:  python generate_data.py
"""

from pathlib import Path
import time

import numpy as np
import pandas as pd

# ----------------------------------------------------------------------------
# 0. GLOBAL CONFIG
# ----------------------------------------------------------------------------
SEED = 42
rng = np.random.default_rng(SEED)

OUT_DIR = Path(__file__).resolve().parent / "output"

START_MONTH = "2025-09-01"
N_MONTHS = 12
MONTH_STARTS = pd.date_range(START_MONTH, periods=N_MONTHS, freq="MS")
WINDOW_END = pd.Timestamp("2026-08-31 23:59:59")

PROMO_MONTH = 8            # index of May 2026 (Sep 2025 = 0)  -> scenario S4
STRESS_START = 8           # stores stressed from May 2026     -> scenario S3
STRESSED_STORES = np.array([4, 6])  # Whitefield, Marathahalli

# monthly new-customer targets (marketing ramp + May-2026 promo spike)
NEW_CUSTOMERS = np.array([1150, 1320, 1520, 1600, 1680, 1820,
                          1950, 2080, 3850, 2150, 2230, 2320])

CHANNELS = np.array(["organic", "referral", "paid_social", "paid_search", "influencer"])
CHANNEL_MIX       = np.array([0.30, 0.12, 0.28, 0.22, 0.08])
CHANNEL_MIX_PROMO = np.array([0.18, 0.09, 0.45, 0.20, 0.08])   # promo pushed on social

PLATFORMS = np.array(["android", "ios"])
PLATFORM_MIX = np.array([0.68, 0.32])

# seasonality multiplier on order frequency (Sep..Aug); Oct-Nov festive, May heat
SEASONAL = np.array([1.00, 1.06, 1.05, 1.02, 0.97, 0.96,
                     1.00, 1.02, 1.06, 1.03, 1.04, 1.03])

# day-of-week order weights (Mon..Sun) — weekend heavy
DOW_W = np.array([0.128, 0.126, 0.130, 0.132, 0.145, 0.175, 0.164])

# hour-of-day order weights — morning + evening peaks
HOUR_W = np.array([0.3, 0.2, 0.15, 0.10, 0.10, 0.30, 0.90, 1.60, 2.40, 2.60,
                   2.30, 2.00, 1.70, 1.40, 1.30, 1.40, 1.70, 2.30, 2.90, 3.10,
                   2.80, 2.20, 1.30, 0.60])
HOUR_W = HOUR_W / HOUR_W.sum()
PEAK_HOURS = np.array([8, 9, 10, 18, 19, 20, 21])

# --- customer behaviour params ------------------------------------------------
ARCHETYPES = np.array(["family_stocker", "snacker", "household_planner", "balanced"])
ARCH_MIX   = np.array([0.28, 0.30, 0.14, 0.28])
ARCH_FREQ_MULT   = {"family_stocker": 1.35, "snacker": 1.00,
                    "household_planner": 0.55, "balanced": 0.95}
ARCH_BASKET_MEAN = {"family_stocker": 4.4, "snacker": 2.2,
                    "household_planner": 2.8, "balanced": 3.4}

BASE_ORDER_RATE = 3.30          # mean orders / active month before multipliers

# activation classes: P(fast <=7d, late 8-45d, never) by channel  -> scenario S1
ACTIVATION = {
    "organic":     (0.84, 0.06, 0.10),
    "referral":    (0.90, 0.04, 0.06),
    "paid_social": (0.72, 0.08, 0.20),
    "paid_search": (0.77, 0.07, 0.16),
    "influencer":  (0.66, 0.09, 0.25),
}
PROMO_PAID_SOCIAL_ACT = (0.78, 0.06, 0.16)   # promo converts installs faster

# monthly churn hazard base by channel (transition t -> t+1)      -> scenario S1
HAZARD_BASE = {
    "organic": 0.34, "referral": 0.27, "paid_social": 0.50,
    "paid_search": 0.45, "influencer": 0.54,
}
# hazard declines with tenure (index = months since first order)
HAZARD_TENURE_MULT = np.array([1.00, 0.60, 0.44, 0.35, 0.30, 0.27,
                               0.25, 0.24, 0.23, 0.22, 0.21, 0.21])
HAZ_BAD_FIRST   = 1.85          # scenario S2: bad first order -> churn
LAM_BAD_FIRST_M0 = 0.40         # S2: bad first order also suppresses orders NOW
LAM_BAD_FIRST_M1 = 0.55         # ... and next month
HAZ_DEAL_SEEKER = 1.35          # scenario S4
HAZ_PROMO_DS    = 2.20          # May-cohort deal seekers after coupons stop
HAZ_STRESS      = 1.40          # scenario S3: stressed home store, m >= May
RESURRECT_P     = 0.035         # small monthly win-back among churned

DEAL_SEEKER_P = {"organic": 0.12, "referral": 0.08, "paid_social": 0.28,
                 "paid_search": 0.22, "influencer": 0.30}
PROMO_DS_BOOST = 0.32           # extra deal-seeker share in May paid cohorts

P_BAD_FIRST_BASE   = 0.13       # P(bad first-order experience), normal store
P_BAD_FIRST_STRESS = 0.38       # ... when home store is stressed that month

# ----------------------------------------------------------------------------
# 1. STORES
# ----------------------------------------------------------------------------
def build_stores() -> pd.DataFrame:
    stores = pd.DataFrame({
        "store_id":   [1, 2, 3, 4, 5, 6],
        "store_code": ["QK-BLR-IND", "QK-BLR-KOR", "QK-BLR-HSR",
                       "QK-BLR-WHT", "QK-BLR-JAY", "QK-BLR-MAR"],
        "zone_name":  ["Indiranagar", "Koramangala", "HSR Layout",
                       "Whitefield", "Jayanagar", "Marathahalli"],
        "city":       ["Bengaluru"] * 6,
        "launch_date": ["2024-11-10", "2024-12-05", "2025-02-18",
                        "2025-04-02", "2025-05-20", "2025-06-15"],
        "base_promise_min": [11, 12, 12, 14, 11, 14],
    })
    return stores

STORE_WEIGHTS = np.array([0.21, 0.20, 0.17, 0.15, 0.14, 0.13])
STORE_PROMISE = np.array([11, 12, 12, 14, 11, 14])   # index = store_id - 1

# ----------------------------------------------------------------------------
# 2. PRODUCTS  (12 categories, ~400 SKUs, category-level margin structure -> S5)
# ----------------------------------------------------------------------------
CATALOG = {
    # category: (n_skus, price_lo, price_hi, margin_pct, items, brands)
    "Fruits & Vegetables": (40, 18, 140, 0.13,
        ["Tomato", "Onion", "Potato", "Banana Robusta", "Apple Shimla", "Carrot",
         "Cucumber", "Spinach Bunch", "Coriander Bunch", "Capsicum", "Cauliflower",
         "Ladies Finger", "Green Chilli", "Ginger", "Garlic", "Sweet Corn",
         "Pomegranate", "Papaya", "Watermelon", "Grapes Green"],
        ["Farm Fresh"]),
    "Dairy, Bread & Eggs": (38, 22, 160, 0.15,
        ["Toned Milk 500ml", "Full Cream Milk 500ml", "Curd Cup 400g", "Paneer 200g",
         "Butter 100g", "Cheese Slices 100g", "Brown Bread 400g", "Milk Bread 400g",
         "White Eggs 6pc", "Brown Eggs 6pc", "Ghee 200ml", "Lassi 200ml",
         "Buttermilk 200ml", "Cream 250ml"],
        ["Kshira", "DawnFarm", "Malnad Dairy"]),
    "Atta, Rice & Dal": (34, 65, 620, 0.16,
        ["Wheat Atta 5kg", "Wheat Atta 1kg", "Sona Masoori Rice 5kg", "Basmati Rice 1kg",
         "Toor Dal 1kg", "Moong Dal 500g", "Chana Dal 1kg", "Urad Dal 500g",
         "Poha 500g", "Rava 500g", "Besan 500g", "Maida 1kg"],
        ["AnnaShree", "GoldHarvest", "Desi Khet"]),
    "Snacks & Biscuits": (40, 10, 180, 0.24,
        ["Potato Chips 52g", "Nachos 60g", "Namkeen Mix 200g", "Bhujia 200g",
         "Glucose Biscuits 100g", "Cream Biscuits 120g", "Digestive Biscuits 250g",
         "Salted Peanuts 160g", "Popcorn 60g", "Cookies 200g", "Rusk 300g",
         "Chikki 100g"],
        ["CrunchBox", "SnaKing", "Tasty Trails"]),
    "Cold Drinks & Juices": (34, 15, 160, 0.21,
        ["Cola 750ml", "Lemon Soda 600ml", "Orange Drink 600ml", "Mango Drink 600ml",
         "Mixed Fruit Juice 1L", "Guava Juice 1L", "Sparkling Water 500ml",
         "Energy Drink 250ml", "Iced Tea 350ml", "Coconut Water 200ml"],
        ["Fizzio", "JuicyRoots", "AquaSpring"]),
    "Instant & Frozen Food": (32, 28, 320, 0.25,
        ["Instant Noodles 70g", "Cup Noodles 70g", "Pasta 500g", "Frozen Peas 500g",
         "Frozen French Fries 420g", "Veg Momos 300g", "Chicken Nuggets 400g",
         "Ready Upma 80g", "Ready Poha 80g", "Instant Soup 45g", "Idli Batter 1kg"],
        ["QuickBite", "FrostFarm", "MomoMagic"]),
    "Tea, Coffee & Health Drinks": (30, 55, 540, 0.26,
        ["Premium Tea 250g", "Green Tea 25 Bags", "Instant Coffee 50g",
         "Filter Coffee 200g", "Malt Drink 500g", "Protein Drink 400g",
         "Masala Chai 250g", "Herbal Tea 25 Bags"],
        ["ChaiVeda", "BrewNest", "VitaFuel"]),
    "Personal Care": (38, 45, 480, 0.33,
        ["Shampoo 340ml", "Conditioner 180ml", "Bath Soap 125g", "Body Wash 250ml",
         "Face Wash 100g", "Toothpaste 150g", "Toothbrush 2pc", "Deodorant 150ml",
         "Hair Oil 200ml", "Moisturizer 200ml", "Sunscreen 50g", "Handwash 200ml",
         "Sanitary Pads 15pc", "Razor 3pc"],
        ["VelvaCare", "PureGlow", "HimShakti"]),
    "Household Essentials": (38, 35, 420, 0.31,
        ["Detergent Powder 1kg", "Liquid Detergent 1L", "Dishwash Gel 750ml",
         "Dishwash Bar 200g", "Floor Cleaner 1L", "Toilet Cleaner 500ml",
         "Garbage Bags 30pc", "Aluminium Foil 9m", "Tissue Box 100pc",
         "Mosquito Repellent 45ml", "Air Freshener 220ml", "Scrub Pad 3pc"],
        ["SparkleHome", "CleanKart", "FreshNest"]),
    "Baby Care": (28, 95, 820, 0.27,
        ["Diapers M 42pc", "Diapers L 34pc", "Baby Wipes 72pc", "Baby Lotion 200ml",
         "Baby Shampoo 200ml", "Baby Powder 200g", "Infant Formula 400g",
         "Baby Cereal 300g"],
        ["TinyHug", "MamaSoft"]),
    "Pet Care": (24, 85, 680, 0.29,
        ["Dog Dry Food 1.2kg", "Dog Treats 100g", "Cat Dry Food 1kg",
         "Cat Treats 50g", "Pet Shampoo 200ml", "Cat Litter 5kg", "Dog Biscuits 500g"],
        ["PawFuel", "WhiskerJoy"]),
    "Ice Cream & Desserts": (30, 35, 260, 0.25,
        ["Vanilla Tub 700ml", "Chocolate Tub 700ml", "Butterscotch Tub 700ml",
         "Kulfi 60ml", "Chocobar 60ml", "Ice Cream Sandwich 80ml", "Ice Cream Cone 110ml",
         "Frozen Dessert Cup 125ml", "Brownie 80g", "Gulab Jamun Tin 500g"],
        ["Creamio", "MithaiWala", "PoleStar"]),
}
PRIVATE_LABEL_BRAND = "QuickKart Daily"
PRIVATE_LABEL_CATS = {"Atta, Rice & Dal", "Snacks & Biscuits", "Household Essentials",
                      "Instant & Frozen Food"}
PL_SHARE = 0.15
PL_MARGIN_BONUS = 0.12


def build_products() -> pd.DataFrame:
    rows = []
    pid = 0
    for cat, (n, lo, hi, margin, items, brands) in CATALOG.items():
        for i in range(n):
            pid += 1
            item = items[i % len(items)]
            is_pl = int(cat in PRIVATE_LABEL_CATS and rng.random() < PL_SHARE)
            brand = PRIVATE_LABEL_BRAND if is_pl else brands[rng.integers(len(brands))]
            # duplicate item names get a variant suffix so names stay unique-ish
            variant = "" if i < len(items) else f" Pack {i // len(items) + 1}"
            # beta(1.2, 3.2) skews prices toward the low end (realistic catalogs)
            price = int(np.round((lo + (hi - lo) * rng.beta(1.2, 3.2)) / 5) * 5)
            price = max(price, lo)
            eff_margin = margin + (PL_MARGIN_BONUS if is_pl else 0.0)
            cost = int(round(price * (1 - eff_margin)))
            rows.append((pid, f"{brand} {item}{variant}", cat, price, cost, is_pl))
    df = pd.DataFrame(rows, columns=["product_id", "product_name", "category",
                                     "unit_price", "unit_cost", "is_private_label"])
    return df


CAT_ORDER = list(CATALOG.keys())
# archetype -> category weights (rows sum to 1), tenure shift applied later (S5)
ARCH_CAT_W = {
    "family_stocker":    np.array([.24, .20, .12, .09, .07, .06, .05, .06, .07, .02, .01, .01]),
    "snacker":           np.array([.06, .10, .02, .24, .20, .12, .05, .05, .04, .00, .01, .11]),
    "household_planner": np.array([.08, .09, .09, .07, .06, .05, .07, .22, .20, .03, .03, .01]),
    "balanced":          np.array([.15, .16, .09, .12, .11, .08, .06, .08, .08, .03, .02, .02]),
}
# S5: with tenure, baskets attach more high-margin categories (tea/coffee,
# personal care, household). Two tiers: months 3-5, months 6+.
TENURE_SHIFT_1 = np.array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.35, 1.90, 1.90, 1.0, 1.0, 1.0])
TENURE_SHIFT_2 = np.array([1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.50, 2.50, 2.50, 1.0, 1.0, 1.0])

# ----------------------------------------------------------------------------
# 3. CUSTOMERS (with hidden behavioural traits, dropped before saving)
# ----------------------------------------------------------------------------
def build_customers() -> pd.DataFrame:
    frames = []
    cid_start = 1
    for m in range(N_MONTHS):
        n = NEW_CUSTOMERS[m]
        mix = CHANNEL_MIX_PROMO if m == PROMO_MONTH else CHANNEL_MIX
        channel = rng.choice(CHANNELS, size=n, p=mix)
        platform = rng.choice(PLATFORMS, size=n, p=PLATFORM_MIX)
        home_store = rng.choice(np.arange(1, 7), size=n, p=STORE_WEIGHTS)

        # signup timestamp: uniform day in month, evening-skewed hour
        month_start = MONTH_STARTS[m]
        days_in_month = (month_start + pd.offsets.MonthEnd(0)).day
        day = rng.integers(0, days_in_month, size=n)
        hour = rng.choice(24, size=n, p=HOUR_W)
        minute = rng.integers(0, 60, size=n)
        signup_ts = (month_start + pd.to_timedelta(day, "D")
                     + pd.to_timedelta(hour, "h") + pd.to_timedelta(minute, "m"))

        df = pd.DataFrame({
            "customer_id": np.arange(cid_start, cid_start + n),
            "signup_ts": signup_ts,
            "acquisition_channel": channel,
            "platform": platform,
            "home_store_id": home_store,
            "_signup_m": m,
        })
        cid_start += n

        # ---- hidden traits ----
        df["_archetype"] = rng.choice(ARCHETYPES, size=n, p=ARCH_MIX)
        df["_freq"] = rng.gamma(1.7, 1 / 1.7, size=n)

        ds_p = np.array([DEAL_SEEKER_P[c] for c in channel])
        if m == PROMO_MONTH:
            ds_p = np.where(np.isin(channel, ["paid_social", "paid_search"]),
                            np.minimum(ds_p + PROMO_DS_BOOST, 0.60), ds_p)
        df["_deal_seeker"] = rng.random(n) < ds_p

        # activation class
        act = np.empty(n, dtype=object)
        u = rng.random(n)
        for ch in CHANNELS:
            mask = channel == ch
            p_fast, p_late, _ = ACTIVATION[ch]
            if m == PROMO_MONTH and ch == "paid_social":
                p_fast, p_late, _ = PROMO_PAID_SOCIAL_ACT
            act[mask & (u < p_fast)] = "fast"
            act[mask & (u >= p_fast) & (u < p_fast + p_late)] = "late"
            act[mask & (u >= p_fast + p_late)] = "never"
        df["_act_class"] = act

        # first-order month
        fom = np.full(n, -1)
        fom[act == "fast"] = m
        late_shift = rng.integers(1, 3, size=n)          # +1 or +2 months
        fom_late = np.minimum(m + late_shift, 99)
        fom[act == "late"] = fom_late[act == "late"]
        fom[(act == "late") & (fom > N_MONTHS - 1)] = -1  # ran out of window
        df["_fom"] = fom
        frames.append(df)

    cust = pd.concat(frames, ignore_index=True)

    # bad first-order experience flag (S2), prob depends on store stress (S3)
    stressed_at_first = (np.isin(cust["home_store_id"], STRESSED_STORES)
                         & (cust["_fom"] >= STRESS_START))
    p_bad = np.where(stressed_at_first, P_BAD_FIRST_STRESS, P_BAD_FIRST_BASE)
    cust["_bad_first"] = (rng.random(len(cust)) < p_bad) & (cust["_fom"] >= 0)
    return cust

# ----------------------------------------------------------------------------
# 4. MONTHLY ACTIVITY SIMULATION (state machine over 12 months)
# ----------------------------------------------------------------------------
def simulate_activity(cust: pd.DataFrame) -> np.ndarray:
    """Returns (n_customers, 12) int matrix of order counts per month."""
    n = len(cust)
    orders_m = np.zeros((n, N_MONTHS), dtype=np.int16)

    fom = cust["_fom"].to_numpy()
    started = np.zeros(n, dtype=bool)
    churned = np.zeros(n, dtype=bool)

    lam_base = (BASE_ORDER_RATE
                * cust["_freq"].to_numpy()
                * cust["_archetype"].map(ARCH_FREQ_MULT).to_numpy())

    hazard_ch = cust["acquisition_channel"].map(HAZARD_BASE).to_numpy()
    bad_first = cust["_bad_first"].to_numpy()
    deal = cust["_deal_seeker"].to_numpy()
    promo_cohort = (cust["_signup_m"] == PROMO_MONTH).to_numpy()
    home_stressed = np.isin(cust["home_store_id"].to_numpy(), STRESSED_STORES)

    for m in range(N_MONTHS):
        newly = fom == m
        started |= newly

        alive = started & ~churned
        lam = lam_base[alive] * SEASONAL[m]
        stress_now = home_stressed[alive] & (m >= STRESS_START)
        lam = np.where(stress_now, lam * 0.94, lam)
        if m == PROMO_MONTH:
            lam = lam * np.where(deal[alive], 1.28, 1.16)
        # S2 aftermath: the month right after a bad first order, ordering slows
        month_after_bad = (fom[alive] == m - 1) & bad_first[alive]
        lam = np.where(month_after_bad, lam * LAM_BAD_FIRST_M1, lam)

        k = rng.poisson(lam)
        k = np.minimum(k, 26)
        idx_alive = np.flatnonzero(alive)
        orders_m[idx_alive, m] = k

        # first-order month: joined mid-month, so ~half a month of activity;
        # exactly 1 guaranteed order + extra orders that collapse after a bad
        # first experience (S2 activation cliff)
        first_now = np.flatnonzero(newly)
        if len(first_now):
            lam_extra = (lam_base[first_now] * SEASONAL[m] * 0.50
                         * np.where(bad_first[first_now], LAM_BAD_FIRST_M0, 1.0))
            orders_m[first_now, m] = 1 + np.minimum(rng.poisson(lam_extra), 25)

        # small win-back among churned customers (resurrection)
        idx_churned = np.flatnonzero(started & churned)
        if len(idx_churned):
            back = idx_churned[rng.random(len(idx_churned)) < RESURRECT_P]
            if len(back):
                kb = np.maximum(rng.poisson(lam_base[back] * 0.6 * SEASONAL[m]), 1)
                orders_m[back, m] = np.minimum(kb, 26)
                churned[back] = False          # re-enter alive pool (high hazard)

        # ---- churn transition at end of month ----
        idx = np.flatnonzero(started & ~churned)
        tenure = m - fom[idx]
        tenure = np.clip(tenure, 0, N_MONTHS - 1)
        h = hazard_ch[idx] * HAZARD_TENURE_MULT[tenure]
        h = np.where(bad_first[idx] & (tenure <= 3), h * HAZ_BAD_FIRST, h)
        h = np.where(deal[idx] & (tenure >= 1), h * HAZ_DEAL_SEEKER, h)
        h = np.where(promo_cohort[idx] & deal[idx] & (m >= PROMO_MONTH + 1),
                     h * HAZ_PROMO_DS, h)
        h = np.where(home_stressed[idx] & (m >= STRESS_START), h * HAZ_STRESS, h)
        h = np.clip(h, 0, 0.92)
        churned[idx[rng.random(len(idx)) < h]] = True

    return orders_m

# ----------------------------------------------------------------------------
# 5. ORDERS
# ----------------------------------------------------------------------------
def _draw_month_ts(m: int, size: int) -> pd.Series:
    """Random timestamps within month m, weekend/evening weighted."""
    month_start = MONTH_STARTS[m]
    days_in_month = (month_start + pd.offsets.MonthEnd(0)).day
    dates = pd.date_range(month_start, periods=days_in_month, freq="D")
    w = DOW_W[dates.dayofweek]
    w = w / w.sum()
    day_idx = rng.choice(days_in_month, size=size, p=w)
    hour = rng.choice(24, size=size, p=HOUR_W)
    minute = rng.integers(0, 60, size=size)
    second = rng.integers(0, 60, size=size)
    return (pd.Series(dates[day_idx])
            + pd.to_timedelta(hour, "h")
            + pd.to_timedelta(minute, "m")
            + pd.to_timedelta(second, "s"))


def build_orders(cust: pd.DataFrame, orders_m: np.ndarray) -> pd.DataFrame:
    fom = cust["_fom"].to_numpy()
    signup_ts = cust["signup_ts"]

    # ---- 5a. first orders (one per activated customer) ----
    act_idx = np.flatnonzero(fom >= 0)
    fast = cust["_act_class"].to_numpy()[act_idx] == "fast"
    delay_h = np.where(
        fast,
        np.minimum(rng.lognormal(np.log(18), 0.9, size=len(act_idx)), 7 * 24),
        rng.uniform(8 * 24, 45 * 24, size=len(act_idx)),
    )
    first_ts = signup_ts.iloc[act_idx].reset_index(drop=True) + pd.to_timedelta(delay_h, "h")
    first_ts = first_ts.clip(upper=WINDOW_END)
    first = pd.DataFrame({
        "customer_id": cust["customer_id"].to_numpy()[act_idx],
        "order_ts": first_ts,
        "is_first": True,
    })

    # ---- 5b. repeat orders from the monthly activity matrix ----
    rep_frames = []
    for m in range(N_MONTHS):
        k = orders_m[:, m].astype(int).copy()
        k[fom == m] -= 1                       # first order handled above
        k = np.maximum(k, 0)
        idx = np.flatnonzero(k > 0)
        if not len(idx):
            continue
        reps = np.repeat(idx, k[idx])
        ts = _draw_month_ts(m, len(reps))
        rep_frames.append(pd.DataFrame({
            "customer_id": cust["customer_id"].to_numpy()[reps],
            "order_ts": ts.to_numpy(),
            "is_first": False,
        }))
    orders = pd.concat([first] + rep_frames, ignore_index=True)

    # repeats must come after the customer's first order
    fmap = first.set_index("customer_id")["order_ts"]
    min_ts = orders["customer_id"].map(fmap)
    bump = pd.to_timedelta(rng.uniform(2, 40, size=len(orders)), "h")
    needs = (~orders["is_first"]) & (orders["order_ts"] <= min_ts)
    orders.loc[needs, "order_ts"] = (min_ts[needs] + bump[needs]).clip(upper=WINDOW_END)

    orders["order_ts"] = pd.to_datetime(orders["order_ts"]).dt.floor("s")
    orders = orders.sort_values(["customer_id", "order_ts"]).reset_index(drop=True)
    orders["order_id"] = np.arange(1, len(orders) + 1)

    # ---- 5c. store, timing, status, experience ----
    n = len(orders)
    cmap = cust.set_index("customer_id")
    home = orders["customer_id"].map(cmap["home_store_id"]).to_numpy()
    other = rng.integers(1, 7, size=n)
    use_home = rng.random(n) < 0.92
    store = np.where(use_home, home, np.where(other == home, (other % 6) + 1, other))
    orders["store_id"] = store

    ts = pd.to_datetime(orders["order_ts"])
    orders["order_ts"] = ts
    month_idx = (ts.dt.year - 2025) * 12 + ts.dt.month - 9
    peak = ts.dt.hour.isin(PEAK_HOURS).to_numpy()
    stressed = np.isin(store, STRESSED_STORES) & (month_idx.to_numpy() >= STRESS_START)

    promised = STORE_PROMISE[store - 1] + 2 * peak.astype(int)
    orders["promised_min"] = promised

    # cancellations
    p_cancel = 0.021 + 0.028 * stressed + 0.008 * peak
    cancelled = rng.random(n) < p_cancel
    orders["status"] = np.where(cancelled, "cancelled", "delivered")

    # actual delivery minutes
    base_noise = rng.normal(-2.2, 2.9, size=n)
    stress_extra = np.where(stressed, rng.gamma(1.8, 2.7, size=n), 0.0)
    actual = promised + base_noise + stress_extra + 1.5 * peak
    # force first-order experience to match the simulated flag (S2 consistency)
    is_first = orders["is_first"].to_numpy()
    bad_first_c = orders["customer_id"].map(cmap["_bad_first"]).to_numpy()
    f_bad = is_first & bad_first_c
    f_good = is_first & ~bad_first_c
    actual = np.where(f_bad, promised + 6 + rng.gamma(1.8, 2.5, size=n), actual)
    actual = np.where(f_good, promised + np.minimum(base_noise, 4.0), actual)
    actual = np.maximum(np.round(actual), 6).astype(int)

    # items missing (delivered only); bad first orders sometimes missing instead of late
    p_missing = 0.018 + 0.075 * stressed
    missing = rng.random(n) < p_missing
    missing = np.where(f_bad & (rng.random(n) < 0.35), True, missing)
    missing = np.where(f_good, False, missing)
    missing = missing & ~cancelled

    orders["actual_delivery_min"] = pd.array(np.where(cancelled, None, actual),
                                             dtype="Int32")
    orders["items_missing"] = missing.astype(int)

    # ratings: ~half of delivered orders; unhappy customers rate more often
    late_min = np.maximum(actual - promised, 0)
    p_rate = 0.48 + 0.18 * ((late_min > 5) | missing)
    rated = (rng.random(n) < p_rate) & ~cancelled
    score = rng.choice([5, 4, 3, 2, 1], size=n, p=[0.70, 0.22, 0.05, 0.02, 0.01])
    score = score - ((late_min >= 1) & (late_min <= 5) & (rng.random(n) < 0.28))
    score = score - ((late_min > 5) & (rng.random(n) < 0.60))
    score = score - ((late_min > 5) & (rng.random(n) < 0.30))
    score = score - (missing & (rng.random(n) < 0.55))
    score = score - (missing & (rng.random(n) < 0.90))
    score = np.clip(score, 1, 5)
    orders["rating"] = pd.array(np.where(rated, score, None), dtype="Int32")

    orders["payment_method"] = rng.choice(
        ["upi", "card", "cod", "wallet"], size=n, p=[0.62, 0.20, 0.11, 0.07])

    orders["_month_idx"] = month_idx
    orders["_stressed"] = stressed
    return orders

# ----------------------------------------------------------------------------
# 6. ORDER ITEMS  (baskets by archetype; tenure shifts to high-margin cats -> S5)
# ----------------------------------------------------------------------------
def build_order_items(orders: pd.DataFrame, cust: pd.DataFrame,
                      products: pd.DataFrame) -> pd.DataFrame:
    cmap = cust.set_index("customer_id")
    arch = orders["customer_id"].map(cmap["_archetype"]).to_numpy()
    signup_m = orders["customer_id"].map(cmap["_signup_m"]).to_numpy()
    tenure = orders["_month_idx"].to_numpy() - signup_m

    # baskets grow modestly with tenure (attach behaviour, S5)
    basket_mean = (pd.Series(arch).map(ARCH_BASKET_MEAN).to_numpy()
                   + 0.5 * (tenure >= 3) + 0.4 * (tenure >= 6))
    n_items = 1 + rng.poisson(basket_mean)
    n_items = np.minimum(n_items, 14)

    order_rep = np.repeat(orders["order_id"].to_numpy(), n_items)
    arch_rep = np.repeat(arch, n_items)
    tier_rep = np.repeat(np.select([tenure >= 6, tenure >= 3], [2, 1], 0), n_items)
    total_items = len(order_rep)

    # category choice per item row (archetype x tenure tier)
    cat_idx = np.empty(total_items, dtype=np.int8)
    for a in ARCHETYPES:
        m_a = arch_rep == a
        for tier, shift in enumerate([None, TENURE_SHIFT_1, TENURE_SHIFT_2]):
            w = ARCH_CAT_W[a] if shift is None else ARCH_CAT_W[a] * shift
            w = w / w.sum()
            m_t = m_a & (tier_rep == tier)
            if m_t.sum():
                cat_idx[m_t] = rng.choice(12, size=m_t.sum(), p=w)

    # SKU within category, popularity-weighted (zipf-ish)
    prod_id = np.empty(total_items, dtype=np.int32)
    price = np.empty(total_items, dtype=np.int32)
    for c, cat in enumerate(CAT_ORDER):
        sub = products[products["category"] == cat]
        ranks = np.arange(1, len(sub) + 1)
        w = 1 / ranks ** 0.9
        w = w / w.sum()
        mask = cat_idx == c
        if mask.sum():
            pick = rng.choice(len(sub), size=mask.sum(), p=w)
            prod_id[mask] = sub["product_id"].to_numpy()[pick]
            price[mask] = sub["unit_price"].to_numpy()[pick]

    # quantity: F&V + dairy more multi-unit
    fv_dairy = cat_idx <= 1
    q = rng.random(total_items)
    qty = np.where(fv_dairy,
                   np.select([q < 0.62, q < 0.89], [1, 2], 3),
                   np.select([q < 0.78, q < 0.95], [1, 2], 3))

    items = pd.DataFrame({
        "order_id": order_rep,
        "product_id": prod_id,
        "quantity": qty.astype(int),
        "unit_price": price,
    })
    items["line_amount"] = items["quantity"] * items["unit_price"]
    # collapse duplicate SKU picks within an order into one line
    items = (items.groupby(["order_id", "product_id"], as_index=False)
                  .agg(quantity=("quantity", "sum"),
                       unit_price=("unit_price", "first"),
                       line_amount=("line_amount", "sum")))
    return items

# ----------------------------------------------------------------------------
# 7. PRICING: totals, discounts, fees
# ----------------------------------------------------------------------------
def apply_pricing(orders: pd.DataFrame, items: pd.DataFrame,
                  cust: pd.DataFrame) -> pd.DataFrame:
    totals = items.groupby("order_id")["line_amount"].sum()
    orders["item_total"] = orders["order_id"].map(totals).fillna(0).astype(int)

    n = len(orders)
    cmap = cust.set_index("customer_id")
    deal = orders["customer_id"].map(cmap["_deal_seeker"]).to_numpy()
    is_first = orders["is_first"].to_numpy()
    in_promo = (orders["_month_idx"] == PROMO_MONTH).to_numpy()
    it = orders["item_total"].to_numpy()

    d_first = np.where(it >= 199, 100, (it * 0.35).astype(int)) * (rng.random(n) < 0.75)
    d_promo = np.minimum((it * 0.20).astype(int), 150) * (rng.random(n) < 0.55)
    p_coupon = 0.06 + 0.10 * deal
    d_coupon = np.minimum((it * 0.10).astype(int), 100) * (rng.random(n) < p_coupon)

    discount = np.where(is_first, d_first, 0)
    discount = np.maximum(discount, np.where(in_promo, d_promo, 0))
    discount = np.maximum(discount, d_coupon)
    orders["discount_amount"] = discount.astype(int)

    orders["delivery_fee"] = np.where(it >= 199, 0, 25).astype(int)
    orders["handling_fee"] = 4
    orders["net_amount"] = (orders["item_total"] - orders["discount_amount"]
                            + orders["delivery_fee"] + orders["handling_fee"])
    return orders

# ----------------------------------------------------------------------------
# 8. APP EVENTS (funnel event log)
# ----------------------------------------------------------------------------
STAGES = ["app_open", "product_view", "add_to_cart", "checkout_start", "payment_success"]

def build_app_events(orders: pd.DataFrame, cust: pd.DataFrame,
                     orders_m: np.ndarray) -> pd.DataFrame:
    cmap = cust.set_index("customer_id")
    frames = []
    sid_counter = 1

    # ---- 8a. converting sessions: one per order ----
    n = len(orders)
    sess_id = np.arange(sid_counter, sid_counter + n)
    sid_counter += n
    start = (orders["order_ts"]
             - pd.to_timedelta(3 + rng.exponential(6, size=n), "m")
             - pd.to_timedelta(rng.integers(0, 60, size=n), "s"))
    platform = orders["customer_id"].map(cmap["platform"]).to_numpy()
    has_search = rng.random(n) < 0.55

    offs_pv = rng.uniform(25, 130, size=n)
    offs_atc = offs_pv + rng.uniform(20, 120, size=n)
    offs_co = offs_atc + rng.uniform(10, 60, size=n)

    def conv_stage(name, ts_arr, mask=None, order_id=None):
        m = np.ones(n, bool) if mask is None else mask
        return pd.DataFrame({
            "session_id": sess_id[m],
            "customer_id": orders["customer_id"].to_numpy()[m],
            "event_name": name,
            "event_ts": ts_arr[m] if isinstance(ts_arr, np.ndarray) else ts_arr[m].to_numpy(),
            "platform": platform[m],
            "order_id": (orders["order_id"].to_numpy()[m] if order_id else
                         np.full(m.sum(), np.nan)),
        })

    start_np = start.to_numpy()
    frames.append(conv_stage("app_open", start_np))
    search_ts = start_np + (rng.uniform(8, 35, size=n) * 1e9).astype("timedelta64[ns]")
    frames.append(conv_stage("search", search_ts, mask=has_search))
    frames.append(conv_stage("product_view",
                             start_np + (offs_pv * 1e9).astype("timedelta64[ns]")))
    frames.append(conv_stage("add_to_cart",
                             start_np + (offs_atc * 1e9).astype("timedelta64[ns]")))
    frames.append(conv_stage("checkout_start",
                             start_np + (offs_co * 1e9).astype("timedelta64[ns]")))
    frames.append(conv_stage("payment_success",
                             orders["order_ts"].to_numpy(), order_id=True))

    # ---- 8b. non-converting sessions per customer-month ----
    fom = cust["_fom"].to_numpy()
    home_stressed = np.isin(cust["home_store_id"].to_numpy(), STRESSED_STORES)
    ios = (cust["platform"] == "ios").to_numpy()

    nc_cust, nc_month, nc_stage = [], [], []
    for m in range(N_MONTHS):
        started = (fom >= 0) & (fom <= m)
        k_orders = orders_m[:, m]
        active = started & (k_orders > 0)
        browsing = started & (k_orders == 0)   # alive-ish but didn't buy

        lam_nc = np.where(active, 1.9 + 0.5 * k_orders, 0.0)
        lam_nc = np.where(browsing, 0.9, lam_nc)
        k_nc = rng.poisson(lam_nc)
        idx = np.flatnonzero(k_nc > 0)
        if not len(idx):
            continue
        reps = np.repeat(idx, k_nc[idx])

        # max stage reached: continue-prob chain with modifiers
        p_pv = np.full(len(reps), 0.58) * np.where(ios[reps], 1.06, 1.0)
        p_atc = np.full(len(reps), 0.42)
        p_co = np.full(len(reps), 0.38)
        if m >= STRESS_START:                   # OOS abandonment (S3)
            p_co = p_co * np.where(home_stressed[reps], 0.72, 1.0)
        u1, u2, u3 = rng.random(len(reps)), rng.random(len(reps)), rng.random(len(reps))
        stage = np.zeros(len(reps), dtype=np.int8)          # 0 = app_open only
        reach_pv = u1 < p_pv
        stage[reach_pv] = 1
        reach_atc = reach_pv & (u2 < p_atc)
        stage[reach_atc] = 2
        reach_co = reach_atc & (u3 < p_co)
        stage[reach_co] = 3
        nc_cust.append(reps)
        nc_month.append(np.full(len(reps), m, dtype=np.int8))
        nc_stage.append(stage)

    # ---- 8c. pre/never-activated browse sessions (signed up, never bought) ----
    never = np.flatnonzero(fom < 0)
    k_pre = rng.integers(1, 3, size=len(never))
    reps = np.repeat(never, k_pre)
    m_pre = cust["_signup_m"].to_numpy()[reps]
    u1, u2 = rng.random(len(reps)), rng.random(len(reps))
    stage = np.zeros(len(reps), dtype=np.int8)
    stage[u1 < 0.45] = 1
    stage[(u1 < 0.45) & (u2 < 0.20)] = 2
    nc_cust.append(reps)
    nc_month.append(m_pre.astype(np.int8))
    nc_stage.append(stage)

    nc_cust = np.concatenate(nc_cust)
    nc_month = np.concatenate(nc_month)
    nc_stage = np.concatenate(nc_stage)
    n_nc = len(nc_cust)
    nc_sess = np.arange(sid_counter, sid_counter + n_nc)

    # timestamps for nc sessions (month-based)
    nc_ts = np.empty(n_nc, dtype="datetime64[ns]")
    for m in range(N_MONTHS):
        mask = nc_month == m
        if mask.sum():
            nc_ts[mask] = _draw_month_ts(m, int(mask.sum())).to_numpy()

    cust_ids = cust["customer_id"].to_numpy()[nc_cust]
    plat = cust["platform"].to_numpy()[nc_cust]
    has_search_nc = (rng.random(n_nc) < 0.5) & (nc_stage >= 1)

    o_pv = (rng.uniform(25, 130, n_nc) * 1e9).astype("timedelta64[ns]")
    o_atc = o_pv + (rng.uniform(20, 120, n_nc) * 1e9).astype("timedelta64[ns]")
    o_co = o_atc + (rng.uniform(10, 60, n_nc) * 1e9).astype("timedelta64[ns]")

    def nc_frame(name, ts, mask):
        return pd.DataFrame({
            "session_id": nc_sess[mask], "customer_id": cust_ids[mask],
            "event_name": name, "event_ts": ts[mask], "platform": plat[mask],
            "order_id": np.full(int(mask.sum()), np.nan),
        })

    frames.append(nc_frame("app_open", nc_ts, np.ones(n_nc, bool)))
    frames.append(nc_frame("search",
                           nc_ts + (rng.uniform(8, 35, n_nc) * 1e9).astype("timedelta64[ns]"),
                           has_search_nc))
    frames.append(nc_frame("product_view", nc_ts + o_pv, nc_stage >= 1))
    frames.append(nc_frame("add_to_cart", nc_ts + o_atc, nc_stage >= 2))
    frames.append(nc_frame("checkout_start", nc_ts + o_co, nc_stage >= 3))

    events = pd.concat(frames, ignore_index=True)
    events["event_ts"] = (pd.to_datetime(events["event_ts"])
                          .dt.floor("s").clip(upper=WINDOW_END))
    events["order_id"] = pd.array(events["order_id"], dtype="Int64")
    events = events.sort_values(["session_id", "event_ts"]).reset_index(drop=True)
    return events

# ----------------------------------------------------------------------------
# 9. MARKETING SPEND
# ----------------------------------------------------------------------------
CPA = {"organic": 0, "referral": 120, "paid_social": 300,
       "paid_search": 270, "influencer": 380}

def build_marketing(cust: pd.DataFrame) -> pd.DataFrame:
    counts = (cust.groupby(["_signup_m", "acquisition_channel"], observed=True)
                  .size().rename("new_customers").reset_index())
    rows = []
    for m in range(N_MONTHS):
        for ch in CHANNELS:
            sub = counts[(counts["_signup_m"] == m)
                         & (counts["acquisition_channel"] == ch)]
            n_new = int(sub["new_customers"].iloc[0]) if len(sub) else 0
            cpa = CPA[ch] * (1.28 if (m == PROMO_MONTH and ch.startswith("paid")) else 1.0)
            spend = int(round(n_new * cpa * rng.normal(1.0, 0.06))) if cpa else 0
            rows.append((MONTH_STARTS[m].date().isoformat(), ch, max(spend, 0)))
    return pd.DataFrame(rows, columns=["month_start", "channel", "spend_inr"])

# ----------------------------------------------------------------------------
# 10. MAIN
# ----------------------------------------------------------------------------
def main():
    t0 = time.time()
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    print("1/6 stores + products ...")
    stores = build_stores()
    products = build_products()

    print("2/6 customers ...")
    cust = build_customers()

    print("3/6 monthly activity simulation ...")
    orders_m = simulate_activity(cust)

    print("4/6 orders + baskets + pricing ...")
    orders = build_orders(cust, orders_m)
    items = build_order_items(orders, cust, products)
    orders = apply_pricing(orders, items, cust)

    print("5/6 app events ...")
    events = build_app_events(orders, cust, orders_m)

    print("6/6 marketing spend + writing CSVs ...")
    marketing = build_marketing(cust)

    # ---- save (drop hidden simulation traits) ----
    cust_out = cust[["customer_id", "signup_ts", "acquisition_channel",
                     "platform", "home_store_id"]].copy()
    orders_out = orders[["order_id", "customer_id", "store_id", "order_ts", "status",
                         "promised_min", "actual_delivery_min", "item_total",
                         "discount_amount", "delivery_fee", "handling_fee",
                         "net_amount", "payment_method", "rating", "items_missing"]]

    # lineterminator="\n" keeps row endings identical on Windows/Mac/Linux so the
    # BULK INSERT scripts (ROWTERMINATOR = '0x0a') work everywhere
    kw = dict(index=False, lineterminator="\n")
    fmt = "%Y-%m-%d %H:%M:%S"
    cust_out.to_csv(OUT_DIR / "customers.csv", date_format=fmt, **kw)
    stores.to_csv(OUT_DIR / "stores.csv", **kw)
    products.to_csv(OUT_DIR / "products.csv", **kw)
    orders_out.to_csv(OUT_DIR / "orders.csv", date_format=fmt, **kw)
    items.to_csv(OUT_DIR / "order_items.csv", **kw)
    events.to_csv(OUT_DIR / "app_events.csv", date_format=fmt, **kw)
    marketing.to_csv(OUT_DIR / "marketing_spend.csv", **kw)

    # ---- console summary ----
    delivered = orders_out[orders_out["status"] == "delivered"]
    print("\n================ GENERATION SUMMARY ================")
    print(f"customers        : {len(cust_out):>9,}")
    print(f"products         : {len(products):>9,}")
    print(f"orders           : {len(orders_out):>9,}  (delivered {len(delivered):,})")
    print(f"order_items      : {len(items):>9,}")
    print(f"app_events       : {len(events):>9,}")
    print(f"GMV (delivered)  : Rs {delivered['item_total'].sum():>12,.0f}")
    print(f"AOV (delivered)  : Rs {delivered['item_total'].mean():>6,.0f}")
    print(f"window           : {orders_out['order_ts'].min()}  ->  {orders_out['order_ts'].max()}")
    print(f"runtime          : {time.time() - t0:,.1f}s")
    print("====================================================")
    print("Injected scenarios (ground truth the SQL analysis should rediscover):")
    print("  S1 channel quality gap   S2 bad-first-order churn   S3 store stress (May+)")
    print("  S4 May promo cohort      S5 margin grows with tenure S6 peaks/seasonality")


if __name__ == "__main__":
    main()
