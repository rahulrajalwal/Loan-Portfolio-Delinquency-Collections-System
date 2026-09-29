"""
Export the Power BI semantic layer to CSV.

Only needed if the MySQL Connector/NET route does not work. A live connection is
preferred (it refreshes), but these CSVs load into exactly the same model.

Credentials come from the stored login-path, so no password appears here.
mysql --batch emits tab-separated output with the literal string NULL for nulls;
pandas converts that to a real null and writes proper quoted CSV.

Run:  python powerbi/export_for_powerbi.py
"""
import io
import os
import subprocess
import sys

import pandas as pd

MYSQL = r"C:\Program Files\MySQL\MySQL Server 8.0\bin\mysql.exe"
OUT = os.path.dirname(os.path.abspath(__file__))
VIEWS = ["pbi_customer", "pbi_account", "pbi_queue",
         "pbi_rollrate", "pbi_vintage", "pbi_signal"]

if not os.path.exists(MYSQL):
    sys.exit(f"mysql.exe not found at {MYSQL}")

print(f"exporting {len(VIEWS)} objects to {OUT}\n")
total_rows = 0

for v in VIEWS:
    proc = subprocess.run(
        [MYSQL, "--login-path=loanproj", "--batch", "--default-character-set=utf8mb4",
         "-e", f"SELECT * FROM loan_portfolio.{v}"],
        capture_output=True, text=True, encoding="utf-8", errors="replace")

    if proc.returncode != 0:
        print(f"  FAILED {v}: {proc.stderr.strip()[:160]}")
        continue

    df = pd.read_csv(io.StringIO(proc.stdout), sep="\t", na_values=["NULL"],
                     keep_default_na=True, low_memory=False)
    path = os.path.join(OUT, f"{v}.csv")
    df.to_csv(path, index=False, encoding="utf-8-sig")   # BOM so Power BI detects UTF-8
    total_rows += len(df)
    print(f"  {v:<16} {len(df):>9,} rows x {len(df.columns):>2} cols  "
          f"-> {os.path.getsize(path)/1024/1024:6.1f} MB")

print(f"\ntotal {total_rows:,} rows exported")
print("\nIn Power BI: Get Data -> Text/CSV, load all six, then create the two")
print("relationships from pbi_customer[SK_ID_CURR] (see BUILD_GUIDE.md section 2).")
