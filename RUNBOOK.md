# Runbook — running the SQL in MySQL Workbench

**Database:** `loan_portfolio` on `localhost:3306`
**Current state:** fully built — 18 tables, 7 views, ~31M rows in base tables.
You do **not** need to rebuild anything to explore the analysis.

---

## 0. Workbench setup — do this first

Two defaults will bite you.

**1. Query timeout.** Several analytical queries run for 4–10 minutes. Workbench
kills queries at 600 seconds by default and you lose the result.

> *Edit → Preferences → SQL Editor → "DBMS connection read timeout interval (in seconds)"*
> Change **600 → 3600**. Then close and reopen the connection tab.

**2. Row limit.** Workbench caps results at 1,000 rows. Fine for every aggregate
here, but it will silently truncate the collections queue (7,211 rows).

> *Edit → Preferences → SQL Editor → "Limit Rows Count"* → set to 0 (no limit),
> or use the dropdown above the results grid per query.

**Running a file:** `File → Open SQL Script`, then **Ctrl+Shift+Enter** to execute
the whole script, or put the cursor in one statement and press **Ctrl+Enter** to
run just that one. Each `SELECT` opens its own result tab — the analysis files
produce 6–15 tabs each. That is expected.

---

## 1. SAFE — read-only. Run these freely, in any order.

These only read. Nothing is created, dropped or changed.

| File | What it answers | Runtime |
|---|---|---|
| `sql/01_data_quality/01_quality_assessment.sql` | 15 data-quality checks; the DPD distribution behind decisions D2/D3 | ~9 min |
| `sql/02_portfolio/01_portfolio_baseline.sql` | Book size, composition, exposure concentration, delinquency, borrower profile | ~9 min |
| `sql/07_early_warning/01_signal_evaluation.sql` | Signal lift/recall, independence, the additive framework, segment stability | ~40 s |
| `sql/09_validation/01_reconciliation.sql` | Re-derives every headline number from base tables | ~10 min |
| `sql/09_validation/02_optimisation.sql` | Execution plans; the fan-out demo (37.5× error) | ~7 s |
| `database/loading/04_verify_load.sql` | Load reconciliation against Phase 2 measurements | ~3 min |

**Start with `02_portfolio` and `08_collections`** if you want to see the analysis
rather than the plumbing.

---

## 2. REBUILD — safe, but recomputes a table. Slower.

These drop and rebuild a `mart_*` table. Re-running is safe and gives identical
results — it just costs time.

| File | Rebuilds | Runtime |
|---|---|---|
| `sql/05_vintage/01_vintage_and_rollrate.sql` | `mart_vintage` | ~6 min |
| `sql/08_collections/01_collections_priority.sql` | `mart_cure_rate`, `mart_collections_queue`, `mart_queue_tiered` | ~12 s |
| `sql/10_powerbi/01_semantic_layer.sql` | the 5 `pbi_*` views + `pbi_signal` | ~8 s |

### ⚠ One exception — `sql/03_repayment/01_repayment_behaviour.sql`

Its **Step 0** runs `ALTER TABLE mart_customer ADD COLUMN ...`. Those columns
already exist, so re-running the file **fails with "Duplicate column name
'N_LATE_FIRST'"** before reaching the analysis.

To re-run just the analysis, skip Step 0: put your cursor below the
`DROP TABLE tmp_first_late;` line and run from `R1` onward with Ctrl+Enter.
Or drop the four columns first:

```sql
ALTER TABLE mart_customer
  DROP COLUMN N_LATE_FIRST,        DROP COLUMN N_LATE_FIRST_30PLUS,
  DROP COLUMN PCT_LATE_FIRST,      DROP COLUMN MAX_DAYS_LATE_FIRST;
```

---

## 3. ⛔ DESTRUCTIVE — do NOT run against the built database

| File | What it would do |
|---|---|
| `database/schema.sql` | **`DROP TABLE` on all 7 base tables.** Wipes ~31M loaded rows. |
| `database/loading/02_load_data.sql` | Re-loads 58M rows. **Duplicates everything** unless tables are empty first. |
| `database/staging_layer.sql` | Rebuilds `stg_installment` + `stg_account_month` (~25 min) |
| `database/mart_layer.sql` | Rebuilds the whole mart (~15 min) |

Only run these if you are rebuilding from scratch — see §5.

---

## 4. Handy starting queries

Paste these straight into Workbench to see the project's main results.

```sql
USE loan_portfolio;

-- The live book
SELECT PRODUCT, COUNT(*) AS accounts, SUM(IS_ACTIVE) AS active,
       ROUND(SUM(CASE WHEN IS_ACTIVE=1 THEN EXPOSURE END)/1000000,1) AS exposure_m,
       SUM(IS_ACTIVE=1 AND DPD_NOW>0) AS delinquent
FROM mart_account GROUP BY PRODUCT WITH ROLLUP;

-- Why severity is the wrong sort key  (the project's core finding)
SELECT BUCKET_ANALYTICAL, COUNT(*) AS accounts,
       ROUND(SUM(EXPOSURE)/1000000,2)               AS exposure_m,
       ROUND(AVG(EXPOSURE),0)                       AS mean_exposure,
       ROUND(AVG(cure_rate)*100,2)                  AS cure_pct,
       ROUND(SUM(cure_weighted_exposure)/1000000,2) AS curable_value_m
FROM mart_collections_queue
GROUP BY BUCKET_ANALYTICAL
ORDER BY FIELD(BUCKET_ANALYTICAL,'1-30','31-90','91-360','360+');

-- The roll-rate matrix (the 90-day cliff)
SELECT PRODUCT, from_bucket, to_bucket, transitions,
       ROUND(100.0*transitions/SUM(transitions)
             OVER (PARTITION BY PRODUCT, from_bucket),2) AS roll_pct
FROM mart_roll_rate
ORDER BY PRODUCT, FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+');

-- The collections queue, top 25
SELECT SK_ID_PREV, PRODUCT, BUCKET_ANALYTICAL, DPD_NOW,
       ROUND(EXPOSURE,0) AS exposure, ROUND(cure_weighted_exposure,0) AS curable_value,
       priority_tier
FROM mart_queue_tiered ORDER BY cure_weighted_exposure DESC LIMIT 25;

-- Early-warning signals vs the 8.0729% base rate
SELECT * FROM pbi_signal ORDER BY lift DESC;
```

---

## 5. Rebuilding from scratch (only if you must)

Order matters. Total ~70 minutes.

1. `database/loading/00_server_setup.sql` — `local_infile`, 2 GB buffer pool
2. `database/schema.sql` — creates DB + 7 tables (PKs only)
3. `database/loading/02_load_data.sql` — 58M rows (**needs `OPT_LOCAL_INFILE=1`**, see below)
4. `database/loading/03_add_indexes.sql` — 6 secondary indexes
5. `database/loading/04_verify_load.sql` — reconciliation
6. `database/loading/05_restore_settings.sql` — durability back to 1
7. `database/staging_layer.sql`
8. `database/mart_layer.sql` — also drops `bureau_balance`
9. Then the analysis files in §1/§2

**For step 3 in Workbench:** `LOAD DATA LOCAL INFILE` is rejected unless the
connection allows it. Edit the connection → **Advanced** tab → *Others* box, add:

```
OPT_LOCAL_INFILE=1
```

Then reconnect. Honestly, the command-line runner is easier for this step:

```bash
powershell -File "C:\Users\acer\Documents\Data_Analytics_Project\Indian_loan_detection\database\run_load.ps1" -Prompt
```

---

## 6. File map

```
database/
  schema.sql                    7 tables, types from measured ranges     ⛔
  staging_layer.sql             stg_installment, stg_account_month       ⛔
  mart_layer.sql                mart_* tables, drops bureau_balance      ⛔
  loading/
    00_server_setup.sql         server settings                          safe
    02_load_data.sql            LOAD DATA for 8 files                    ⛔
    03_add_indexes.sql          6 secondary indexes                      rebuild
    04_verify_load.sql          load reconciliation                      SAFE
    05_restore_settings.sql     restore durability                       safe
  run_load.ps1 / run_sql.ps1    command-line runners
sql/
  01_data_quality/              15 quality checks, D2/D3 evidence        SAFE
  02_portfolio/                 book, exposure, delinquency, D4          SAFE
  03_repayment/                 repayment behaviour, signals             ⚠ see §2
  05_vintage/                   vintage curves + roll-rate matrix        rebuild
  07_early_warning/             signal lift/recall/stacking              SAFE
  08_collections/               cure rates, priority tiers, the queue    rebuild
  09_validation/                reconciliation + optimisation            SAFE
  10_powerbi/                   semantic layer views                     rebuild
python/  validate_independent.py    pandas cross-check (9/9 pass)
powerbi/ BUILD_GUIDE.md + 6 CSVs    dashboard spec and data
```

**Note on folder numbering:** `04_delinquency` and `06_roll_rate` from the original
plan don't exist as separate folders. Delinquency analysis lives in `02_portfolio`
and `03_repayment`; roll-rate lives with vintage in `05_vintage`, because both
read the same panel and splitting them would have meant scanning it twice.
