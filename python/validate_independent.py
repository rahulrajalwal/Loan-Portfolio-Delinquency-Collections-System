"""
PHASE 11B - INDEPENDENT VALIDATION

Re-derives the project's headline numbers from the ORIGINAL CSVs using pandas.
This is deliberately a third path:

    CSV -> MySQL base tables -> staging -> mart -> reported number     (the project)
    CSV -> MySQL base tables, different query                          (Phase 11A)
    CSV -> pandas                                                      (THIS FILE)

Different engine, different code, same source files. If all three agree, the
number is trustworthy in a way that no single computation can be.

Run:  python python/validate_independent.py
"""
import os
import pandas as pd

RAW = r"C:\Users\acer\Documents\Data_Analytics_Project\Indian_loan_detection\data\raw"
P = lambda f: os.path.join(RAW, f)

# (label, value reported by the project, tolerance)
EXPECT = {
    "TARGET base rate %":                (8.0729,     0.0001),
    "train customers":                   (307511,     0),
    "defaults":                          (24825,      0),
    "split payments (F1)":               (653483,     0),
    "accounts at latest month":          (1040632,    0),
    "active accounts":                   (327101,     0),
    "delinquent active (queue size)":    (7211,       0),
    "CARD exposure (millions)":          (7774.0,     0.1),
    "POS 1-30 -> 31-90 transitions":     (7291,       0),
}

results = []
def check(label, actual):
    exp, tol = EXPECT[label]
    ok = abs(actual - exp) <= tol
    results.append((label, exp, actual, ok))
    print(f"  {'PASS' if ok else 'FAIL'}  {label:<34} expected={exp:>12,}  actual={actual:>12,}")

print("=" * 92)
print("PHASE 11B - INDEPENDENT VALIDATION (pandas, straight from CSV)")
print("=" * 92)

# ---- 1. outcome ------------------------------------------------------
print("\n[1] application_train.csv - outcome")
app = pd.read_csv(P("application_train.csv"), usecols=["SK_ID_CURR", "TARGET"])
check("train customers", len(app))
check("defaults", int(app.TARGET.sum()))
check("TARGET base rate %", round(app.TARGET.mean() * 100, 4))
del app

# ---- 2. grain (F1) ---------------------------------------------------
print("\n[2] installments_payments.csv - grain")
ip = pd.read_csv(P("installments_payments.csv"),
                 usecols=["SK_ID_PREV", "NUM_INSTALMENT_VERSION", "NUM_INSTALMENT_NUMBER"])
n_rows = len(ip)
n_uniq = len(ip.drop_duplicates())
check("split payments (F1)", n_rows - n_uniq)
del ip

# ---- 3. the book -----------------------------------------------------
print("\n[3] POS_CASH_balance.csv + credit_card_balance.csv - the book")
pos = pd.read_csv(P("POS_CASH_balance.csv"),
                  usecols=["SK_ID_PREV", "MONTHS_BALANCE", "NAME_CONTRACT_STATUS", "SK_DPD"])
card = pd.read_csv(P("credit_card_balance.csv"),
                   usecols=["SK_ID_PREV", "MONTHS_BALANCE", "NAME_CONTRACT_STATUS",
                            "SK_DPD", "AMT_BALANCE"])

def latest(df):
    """One row per account: its highest (latest) MONTHS_BALANCE."""
    idx = df.groupby("SK_ID_PREV")["MONTHS_BALANCE"].idxmax()
    return df.loc[idx]

pos_l, card_l = latest(pos), latest(card)
check("accounts at latest month", len(pos_l) + len(card_l))

active = (pos_l.NAME_CONTRACT_STATUS == "Active").sum() + \
         (card_l.NAME_CONTRACT_STATUS == "Active").sum()
check("active accounts", int(active))

delinq = ((pos_l.NAME_CONTRACT_STATUS == "Active") & (pos_l.SK_DPD > 0)).sum() + \
         ((card_l.NAME_CONTRACT_STATUS == "Active") & (card_l.SK_DPD > 0)).sum()
check("delinquent active (queue size)", int(delinq))

card_exp = card_l.loc[card_l.NAME_CONTRACT_STATUS == "Active", "AMT_BALANCE"].sum()
check("CARD exposure (millions)", round(card_exp / 1_000_000, 1))
del card, card_l, pos_l

# ---- 4. one roll-rate cell ------------------------------------------
print("\n[4] POS_CASH_balance.csv - roll rate, one cell")
def bucket(d):
    if d == 0:   return "0-current"
    if d <= 30:  return "1-30"
    if d <= 90:  return "31-90"
    if d <= 360: return "91-360"
    return "360+"

pos = pos.sort_values(["SK_ID_PREV", "MONTHS_BALANCE"])
pos["b"] = pos.SK_DPD.map(bucket)
pos["pb"] = pos.groupby("SK_ID_PREV")["b"].shift(1)
pos["pm"] = pos.groupby("SK_ID_PREV")["MONTHS_BALANCE"].shift(1)
consecutive = pos.MONTHS_BALANCE == pos.pm + 1          # the gap guard
n_trans = int(((pos.pb == "1-30") & (pos.b == "31-90") & consecutive).sum())
check("POS 1-30 -> 31-90 transitions", n_trans)
del pos

# ---- summary ---------------------------------------------------------
print("\n" + "=" * 92)
passed = sum(1 for *_, ok in results if ok)
print(f"RESULT: {passed} of {len(results)} checks passed")
if passed < len(results):
    print("\nFAILURES:")
    for label, exp, act, ok in results:
        if not ok:
            print(f"  {label}: expected {exp:,}, got {act:,}, diff {act-exp:+,}")
print("=" * 92)
