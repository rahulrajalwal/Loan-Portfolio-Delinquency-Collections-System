"""
Phase 4 — generate LOAD DATA LOCAL INFILE statements.

Why generated rather than hand-written:
  * 219 columns across 8 loads
  * every NULLABLE column needs @var + NULLIF(@var,'') or MySQL writes 0 / '' instead of NULL
  * column order must match the CSV header exactly

Format facts measured from the files (Phase 4):
  * LF line endings          -> LINES TERMINATED BY '\\n'
  * quoted fields with commas -> OPTIONALLY ENCLOSED BY '"'   (e.g. "Spouse, partner")
  * header row present        -> IGNORE 1 LINES
  * empty field = NULL        -> NULLIF(@v,'')
"""
import re, os, csv

BASE   = r"C:\Users\acer\Documents\Data_Analytics_Project\Indian_loan_detection"
RAW    = os.path.join(BASE, "data", "raw").replace("\\", "/")
SCHEMA = os.path.join(BASE, "database", "schema.sql")
OUT    = os.path.join(BASE, "database", "loading", "02_load_data.sql")

# ---- parse schema.sql for column nullability -------------------------------
sql = open(SCHEMA, encoding="utf-8").read()
tables = {}
for m in re.finditer(r"CREATE TABLE `(\w+)` \((.*?)\n\) ENGINE", sql, re.S):
    tbl, body = m.group(1), m.group(2)
    cols = {}
    for line in body.split("\n"):
        cm = re.match(r"\s*`(\w+)`\s+(.*?)\s+(NOT NULL|NULL)\b", line)
        if cm:
            cols[cm.group(1)] = (cm.group(3) == "NULL")   # True => nullable
    tables[tbl] = cols

def header(csv_name):
    with open(os.path.join(RAW, csv_name), newline="", encoding="utf-8") as f:
        return next(csv.reader(f))

def build(csv_name, tbl, extra_set=None, skip_cols=()):
    """Emit one LOAD DATA statement."""
    hdr  = header(csv_name)
    cols = tables[tbl]
    field_list, set_list = [], []
    for c in hdr:
        if c in skip_cols:
            field_list.append("@ignored")
            continue
        if c not in cols:
            raise SystemExit(f"column {c} in {csv_name} not found in table {tbl}")
        if cols[c]:                       # nullable -> route through a variable
            field_list.append(f"@v_{c}")
            set_list.append(f"  `{c}` = NULLIF(@v_{c}, '')")
        else:
            field_list.append(f"`{c}`")
    if extra_set:
        set_list.insert(0, extra_set)

    s  = f"-- {csv_name}  ->  {tbl}\n"
    s += f"LOAD DATA LOCAL INFILE '{RAW}/{csv_name}'\n"
    s += f"INTO TABLE `{tbl}`\n"
    s += "  FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '\"'\n"
    s += "  LINES TERMINATED BY '\\n'\n"
    s += "  IGNORE 1 LINES\n"
    s += "  (" + ", ".join(field_list) + ")\n"
    if set_list:
        s += "SET\n" + ",\n".join(set_list) + "\n"
    s = s.rstrip() + ";\n"
    s += "SHOW WARNINGS;\n"
    return s

parts = ["""-- =====================================================================
-- Phase 4 - bulk load.  Run AFTER 00_server_setup.sql and schema.sql.
-- Order matters only for readability; there are no FK constraints (Phase 3).
-- =====================================================================
USE loan_portfolio;

-- Session tuning for bulk load. unique_checks stays ON deliberately:
-- it is what proves the Phase 2 primary keys actually hold.
SET SESSION foreign_key_checks = 0;
SET autocommit = 0;
"""]

parts.append(build("application_train.csv", "application", extra_set="  `SOURCE` = 'train'"))
parts.append("COMMIT;\n")
parts.append(build("application_test.csv",  "application", extra_set="  `SOURCE` = 'test'"))
parts.append("COMMIT;\n")
for csv_name, tbl in [("bureau.csv", "bureau"),
                      ("bureau_balance.csv", "bureau_balance"),
                      ("previous_application.csv", "previous_application"),
                      ("POS_CASH_balance.csv", "pos_cash_balance"),
                      ("credit_card_balance.csv", "credit_card_balance"),
                      ("installments_payments.csv", "installments_payments")]:
    parts.append(build(csv_name, tbl))
    parts.append("COMMIT;\n")

parts.append("""
SET SESSION foreign_key_checks = 1;
SET autocommit = 1;
""")

os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, "w", encoding="utf-8").write("\n".join(parts))
print("written:", OUT)
print("\n--- preview: pos_cash_balance ---")
print(build("POS_CASH_balance.csv", "pos_cash_balance"))
