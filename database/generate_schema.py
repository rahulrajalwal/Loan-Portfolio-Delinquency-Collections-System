"""
Phase 3 — MySQL schema generator.

Scans each CSV and emits CREATE TABLE DDL using the SMALLEST SAFE MySQL type for
every column, based on measured min/max/scale/length rather than assumption.

Why generate instead of hand-write:
  * 219 columns across 7 tables is too many to type without error
  * type choice should follow measured data, not guesswork
  * re-runnable if the source data ever changes

Type rules
  integers   -> TINYINT / SMALLINT / MEDIUMINT / INT / BIGINT, UNSIGNED when min >= 0
  decimals   -> DECIMAL(p, s) sized from the observed magnitude and scale
  short text -> CHAR(1) when maxlen == 1; ENUM when few distinct values on a large
                table (stores a 1-2 byte index, not the string); else VARCHAR
"""
import pandas as pd, numpy as np, os, math, json, gc

RAW = r"C:\Users\acer\Documents\Data_Analytics_Project\Indian_loan_detection\data\raw"
OUT = r"C:\Users\acer\Documents\Data_Analytics_Project\Indian_loan_detection\database\schema.sql"
CHUNK = 2_000_000

SIGNED   = [("TINYINT", -128, 127), ("SMALLINT", -32768, 32767),
            ("MEDIUMINT", -8388608, 8388607), ("INT", -2147483648, 2147483647),
            ("BIGINT", -2**63, 2**63 - 1)]
UNSIGNED = [("TINYINT", 0, 255), ("SMALLINT", 0, 65535), ("MEDIUMINT", 0, 16777215),
            ("INT", 0, 4294967295), ("BIGINT", 0, 2**64 - 1)]

# Tables large enough that ENUM's 1-2 byte storage is worth the rigidity
BIG = {"POS_CASH_balance.csv", "credit_card_balance.csv",
       "installments_payments.csv", "bureau_balance.csv"}

TABLE_NAME = {
    "application_train.csv": "application", "application_test.csv": "application",
    "bureau.csv": "bureau", "bureau_balance.csv": "bureau_balance",
    "previous_application.csv": "previous_application",
    "POS_CASH_balance.csv": "pos_cash_balance",
    "credit_card_balance.csv": "credit_card_balance",
    "installments_payments.csv": "installments_payments",
}

def int_type(lo, hi):
    table = UNSIGNED if lo >= 0 else SIGNED
    for name, a, b in table:
        if lo >= a and hi <= b:
            return name + (" UNSIGNED" if lo >= 0 else "")
    return "BIGINT"

def scan(path, is_big):
    """Return {col: profile} measured across the whole file."""
    prof = {}
    for ch in pd.read_csv(path, chunksize=CHUNK, low_memory=False):
        for c in ch.columns:
            s = ch[c]
            p = prof.setdefault(c, {"kind": None, "min": None, "max": None, "scale": 0,
                                    "maxlen": 0, "vals": set(), "nulls": 0, "n": 0})
            p["n"] += len(s); p["nulls"] += int(s.isna().sum())
            v = s.dropna()
            if pd.api.types.is_numeric_dtype(s):
                p["kind"] = "num" if p["kind"] in (None, "num") else p["kind"]
                if len(v):
                    lo, hi = float(v.min()), float(v.max())
                    p["min"] = lo if p["min"] is None else min(p["min"], lo)
                    p["max"] = hi if p["max"] is None else max(p["max"], hi)
                    if (v % 1 != 0).any():
                        # observed decimal places, capped
                        frac = v[v % 1 != 0].astype(str).str.split(".").str[-1].str.len()
                        p["scale"] = max(p["scale"], min(int(frac.max()), 8))
            else:
                p["kind"] = "txt"
                if len(v):
                    sv = v.astype(str)
                    p["maxlen"] = max(p["maxlen"], int(sv.str.len().max()))
                    if len(p["vals"]) < 60:
                        p["vals"].update(sv.unique().tolist())
        del ch; gc.collect()
    return prof

def mysql_type(col, p, is_big):
    # All monetary columns share ONE type. Mixed scales (DECIMAL(9,1) vs DECIMAL(11,3))
    # would give different rounding behaviour in cross-table arithmetic such as
    # AMT_PAYMENT - AMT_INSTALMENT, or AMT_BALANCE / AMT_CREDIT_LIMIT_ACTUAL.
    # Max observed magnitude is 585,000,000 and max observed scale is 3, so (15,3) is safe.
    if col.startswith("AMT_") and p["kind"] == "num":
        return "DECIMAL(15,3)"
    if p["kind"] == "txt":
        if p["maxlen"] == 1:
            return "CHAR(1)"
        if is_big and 0 < len(p["vals"]) <= 15:
            vals = ",".join("'" + v.replace("'", "''") + "'" for v in sorted(p["vals"]))
            return f"ENUM({vals})"
        return f"VARCHAR({max(10, int(math.ceil(p['maxlen'] * 1.25 / 5) * 5))})"
    if p["min"] is None:
        return "VARCHAR(50)"
    if p["scale"] == 0:
        return int_type(int(math.floor(p["min"])), int(math.ceil(p["max"])))
    intdigits = max(len(str(int(abs(p["min"])))), len(str(int(abs(p["max"]))))) + 1
    return f"DECIMAL({min(intdigits + p['scale'], 30)},{p['scale']})"

# ---------------------------------------------------------------- build DDL
FILES = ["application_train.csv", "bureau.csv", "bureau_balance.csv",
         "previous_application.csv", "POS_CASH_balance.csv",
         "credit_card_balance.csv", "installments_payments.csv"]

ddl, notes = [], []
for fn in FILES:
    print(f"scanning {fn} ...", flush=True)
    prof = scan(os.path.join(RAW, fn), fn in BIG)
    tbl = TABLE_NAME[fn]
    lines = []
    if tbl == "application":
        lines.append("  `SOURCE` ENUM('train','test') NOT NULL "
                     "COMMENT 'D5: train and test unioned for referential completeness'")
    for c, p in prof.items():
        t = mysql_type(c, p, fn in BIG)
        null = "NULL" if p["nulls"] else "NOT NULL"
        if tbl == "application" and c == "TARGET":
            null = "NULL"          # test rows carry no outcome
        lines.append(f"  `{c}` {t} {null}")
        if p["kind"] == "num" and p["max"] is not None and p["max"] > 255 and p["max"] <= 65535 \
           and p["scale"] == 0 and p["min"] >= 0:
            notes.append(f"{tbl}.{c}: max={int(p['max'])} -> needs {t} (TINYINT would truncate)")
    ddl.append((tbl, lines))
    del prof; gc.collect()

PK = {
    "application":            "PRIMARY KEY (`SK_ID_CURR`)",
    "bureau":                 "PRIMARY KEY (`SK_ID_BUREAU`)",
    "bureau_balance":         "PRIMARY KEY (`SK_ID_BUREAU`,`MONTHS_BALANCE`)",
    "previous_application":   "PRIMARY KEY (`SK_ID_PREV`)",
    "pos_cash_balance":       "PRIMARY KEY (`SK_ID_PREV`,`MONTHS_BALANCE`)",
    "credit_card_balance":    "PRIMARY KEY (`SK_ID_PREV`,`MONTHS_BALANCE`)",
    # F1: no natural key exists - one row is a PAYMENT EVENT, not an installment
    "installments_payments":  "PRIMARY KEY (`payment_id`)",
}
IDX = {
    "bureau":                ["KEY `ix_bureau_curr` (`SK_ID_CURR`)"],
    "previous_application":  ["KEY `ix_prev_curr` (`SK_ID_CURR`)"],
    "pos_cash_balance":      ["KEY `ix_pos_curr` (`SK_ID_CURR`)"],
    "credit_card_balance":   ["KEY `ix_cc_curr` (`SK_ID_CURR`)"],
    "installments_payments": ["KEY `ix_inst_prev_num` (`SK_ID_PREV`,`NUM_INSTALMENT_NUMBER`)",
                              "KEY `ix_inst_curr` (`SK_ID_CURR`)"],
}

with open(OUT, "w", encoding="utf-8") as f:
    f.write("-- Loan Portfolio, Delinquency & Collections Intelligence System\n")
    f.write("-- Phase 3 schema. Types derived from MEASURED value ranges (see generate_schema.py).\n")
    f.write("-- NOTE: no FOREIGN KEY constraints on SK_ID_PREV / SK_ID_BUREAU relationships -\n")
    f.write("--       Phase 2 finding F3 measured genuine orphans (4.0% POS, 10.9% card,\n")
    f.write("--       3.9% installments, 5.3% bureau_balance). Declaring them would reject real rows.\n\n")
    f.write("CREATE DATABASE IF NOT EXISTS loan_portfolio\n"
            "  DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci;\nUSE loan_portfolio;\n\n")
    for tbl, lines in ddl:
        f.write(f"DROP TABLE IF EXISTS `{tbl}`;\nCREATE TABLE `{tbl}` (\n")
        if tbl == "installments_payments":
            f.write("  `payment_id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT "
                    "COMMENT 'surrogate: F1 shows no natural PK exists',\n")
        f.write(",\n".join(lines))
        f.write(",\n  " + PK[tbl])
        # Secondary indexes are DELIBERATELY not created here. Maintaining them across
        # 13.6M inserts is far slower than building each once over a finished table.
        # They live in database/loading/03_add_indexes.sql, applied after the bulk load.
        f.write("\n) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;\n\n")

IDXFILE = os.path.join(os.path.dirname(OUT), "loading", "03_add_indexes.sql")
os.makedirs(os.path.dirname(IDXFILE), exist_ok=True)
with open(IDXFILE, "w", encoding="utf-8") as f:
    f.write("-- Phase 4 - secondary indexes, applied AFTER the bulk load.\n")
    f.write("-- Building an index once over a finished table beats maintaining it per-insert.\n")
    f.write("-- Each index maps to a named analytical module (see docs/03_database_architecture.md).\n\n")
    f.write("USE loan_portfolio;\n\n")
    for tbl, idxs in IDX.items():
        for i in idxs:
            m = __import__("re").match(r"KEY `(\w+)` \((.*)\)", i)
            f.write(f"ALTER TABLE `{tbl}` ADD INDEX `{m.group(1)}` ({m.group(2)});\n")
    f.write("\nANALYZE TABLE `application`, `bureau`, `bureau_balance`, `previous_application`,\n"
            "              `pos_cash_balance`, `credit_card_balance`, `installments_payments`;\n")
print("written:", IDXFILE)

print(f"\nwritten: {OUT}")
if notes:
    print("\ntype-safety catches:")
    for n in sorted(set(notes))[:20]:
        print("  " + n)
