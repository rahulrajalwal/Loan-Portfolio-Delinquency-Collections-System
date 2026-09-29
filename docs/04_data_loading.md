# Phase 4 — Loading into MySQL

**Date:** 2026-09-06
**Status:** ✅ Complete. 58,441,594 rows loaded, every verification check passed.
**Total runtime:** 21 minutes end to end.

---

## 4.1 Server configuration problems found

The installer defaults would have made this load slow or impossible.

| Setting | Installed value | Changed to | Why |
|---|---|---|---|
| `local_infile` | OFF (MySQL 8 default) | `1` | `secure-file-priv` restricts server-side `LOAD DATA INFILE` to `C:/ProgramData/MySQL/MySQL Server 8.0/Uploads`. Our CSVs live in the project folder, so the file must be pushed from the **client** with `LOCAL`. |
| `innodb_buffer_pool_size` | **128 MB** | **2 GB** | The cache for data and index pages. At 128 MB almost every page read goes to disk. Dynamic in MySQL 8 — resized online, no restart. |
| `innodb_flush_log_at_trx_commit` | 1 | 2 during load, **restored to 1** | Sync-per-commit → sync-per-second. Acceptable only because this is reproducible static data. |

All three are dynamic. **No service restart was required.**

---

## 4.2 Two file-format traps

### Embedded commas
`application_train`, `application_test` and `previous_application` contain quoted fields with commas
inside — `Spouse, partner`, `Stone, brick`. 72,292 rows in the first 300,000 of `application_train`
alone. Without `OPTIONALLY ENCLOSED BY '"'` those rows would shear into the wrong columns.

### Empty fields are not NULL
An empty CSV field loaded into a numeric column becomes **`0`**, not NULL. `bureau.AMT_ANNUITY` has
1,226,791 empty fields — they would have become 1.2 million zero-annuity loans, silently corrupting
every exposure and annuity average in the project.

Every nullable column therefore routes through a user variable:

```sql
  (`SK_ID_PREV`, `SK_ID_CURR`, `MONTHS_BALANCE`, @v_CNT_INSTALMENT, ...)
SET
  `CNT_INSTALMENT` = NULLIF(@v_CNT_INSTALMENT, '')
```

Generated programmatically for all 219 columns (`database/generate_load_sql.py`) rather than
hand-written.

---

## 4.3 Indexes built after loading, not during

Originally the six secondary indexes sat inside `CREATE TABLE`, meaning InnoDB would maintain them
across all 13.6M inserts into `installments_payments`. They were moved to
`loading/03_add_indexes.sql` and applied afterwards.

**Measured cost of building all six over finished tables: 1.9 minutes.**

---

## 4.4 Load results

| Table | Records | Deleted | Skipped | Warnings |
|---|---:|---:|---:|---:|
| `application` (train) | 307,511 | 0 | **0** | 798,422 |
| `application` (test) | 48,744 | 0 | **0** | 134,962 |
| `bureau` | 1,716,428 | 0 | **0** | 7 |
| `bureau_balance` | 27,299,925 | 0 | **0** | 0 |
| `previous_application` | 1,670,214 | 0 | **0** | 416,152 |
| `pos_cash_balance` | 10,001,358 | 0 | **0** | 0 |
| `credit_card_balance` | 3,840,312 | 0 | **0** | 0 |
| `installments_payments` | 13,605,401 | 0 | **0** | 0 |
| **Total** | **58,441,594** | 0 | **0** | |

### The warnings are all one benign class

Grouping every warning emitted across the entire load gives exactly one type:

```
Note 1265: Data truncated for column X at row N
```

**Zero code-1264 ("Out of range value"), zero errors, zero skipped rows.**

The distinction matters:
- **1265 (Note)** — decimal places dropped. The value is rounded.
- **1264 (Warning)** — the *integer* part was clipped. This destroys data.

Columns affected, all declared `DECIMAL(10,8)` and all normalized to `[0,1]`:
`EXT_SOURCE_1/2/3`, `REGION_POPULATION_RELATIVE`, `RATE_DOWN_PAYMENT`,
`RATE_INTEREST_PRIMARY/PRIVILEGED`, and the building `_AVG`/`_MODE`/`_MEDI` columns.

Source values carry ~16 decimal places (e.g. `0.0830369673913225`); they are stored to 8
(`0.08303697`). Eight decimal places on a normalized score gives 10^8 distinct levels — far beyond
any analytical resolution we need. `bureau.AMT_CREDIT_SUM_DEBT`/`_LIMIT` at `DECIMAL(15,3)` rounds
money to three decimals: 7 warnings across 1.7M rows.

**Decision: accepted, not reloaded.** Logged here rather than hidden.

---

## 4.5 Verification — every check passed

### Row-count reconciliation (against Phase 2 CSV measurements)
All 8 loads: **diff = 0**.

### Value-range checks — did anything truncate?
| Column | Actual max | Expected (Phase 2) | |
|---|---:|---:|---|
| `pos_cash_balance.SK_DPD` | 4,231 | 4,231 | ✅ |
| `pos_cash_balance.SK_DPD_DEF` | 3,595 | 3,595 | ✅ |
| `credit_card_balance.SK_DPD` | 3,260 | 3,260 | ✅ |
| `installments_payments.NUM_INSTALMENT_NUMBER` | 277 | 277 | ✅ |
| `bureau.CREDIT_DAY_OVERDUE` | 2,792 | 2,792 | ✅ |
| `application.DAYS_EMPLOYED` (sentinel) | 365,243 | 365,243 | ✅ |

Money precision intact: `MAX(AMT_INSTALMENT) = MAX(AMT_PAYMENT) = 3,771,487.845` — three decimals
preserved. `SUM(AMT_PAYMENT) = 234,482,862,799.620`.

### NULL handling — empty fields became NULL, not 0
| Column | NULLs | Expected | |
|---|---:|---:|---|
| `installments_payments.DAYS_ENTRY_PAYMENT` | 2,905 | 2,905 | ✅ |
| `installments_payments.AMT_PAYMENT` | 2,905 | 2,905 | ✅ |
| `pos_cash_balance.CNT_INSTALMENT` | 26,071 | 26,071 | ✅ |
| `application.AMT_ANNUITY` (train) | 12 | 12 | ✅ |
| `application.EXT_SOURCE_1` (train) | 173,378 | 173,378 | ✅ |
| `bureau.AMT_ANNUITY` | 1,226,791 | 1,226,791 | ✅ |

### Quoted fields survived
`NAME_TYPE_SUITE = 'Spouse, partner'` → **11,370 rows**, matching Phase 2 exactly.
`COUNT(DISTINCT ORGANIZATION_TYPE)` = **58**, matching Phase 2.

### Base rate
`SOURCE='train'`: 307,511 rows, 24,825 defaults, **`TARGET` = 8.0729%** — identical to the CSV
measurement.
`SOURCE='test'`: 48,744 rows, all with NULL `TARGET`, exactly as designed in **[D5]**.

### Referential integrity re-measured in-database
| Relationship | Orphans | Expected (Phase 2) | |
|---|---:|---:|---|
| `bureau` → `application` | **0** | 0 | ✅ F2 confirmed |
| `previous_application` → `application` | **0** | 0 | ✅ F2 confirmed |
| `pos_cash_balance` → `previous_application` | 37,422 | 37,422 | ✅ F3 |
| `credit_card_balance` → `previous_application` | 11,372 | 11,372 | ✅ F3 |
| `installments_payments` → `previous_application` | 38,847 | 38,847 | ✅ F3 |
| `bureau_balance` → `bureau` | 43,041 | 43,041 | ✅ F3 |

**F2 is now proven in the database:** loading `application_test` alongside `application_train`
reduced the apparent orphan rate from ~14% to exactly zero.

### Grain reproduced
`installments_payments`: 13,605,401 rows / 12,951,918 distinct triples = **653,483 split payments** —
F1 reproduces exactly.

---

## 4.6 Actual storage vs estimate

| Table | Data MB | Index MB | Total MB |
|---|---:|---:|---:|
| `bureau_balance` | 1,700.0 | 0.0 | 1,700.0 |
| `installments_payments` | 792.0 | 525.7 | 1,317.7 |
| `credit_card_balance` | 809.0 | 53.6 | 862.6 |
| `pos_cash_balance` | 654.0 | 137.6 | 791.6 |
| `previous_application` | 614.0 | 21.5 | 635.5 |
| `bureau` | 395.9 | 22.5 | 418.5 |
| `application` | 276.9 | 0.0 | 276.9 |
| **Total** | | | **5.86 GB** |

**My Phase 3 estimate was 3.8 GB. Actual is 5.86 GB — the estimate was 35% low.** InnoDB page
overhead, the clustered-index structure and fill-factor slack account for the gap; row-size
arithmetic consistently under-predicts real InnoDB footprint.

Disk after loading: **37.4 GB free** (was 46.8 GB before the CSVs). Comfortable.

---

## 4.7 Timings

| Step | Duration |
|---|---:|
| Server settings | ~0 min |
| Create database + 7 tables | ~0 min |
| **Bulk load 58.4M rows** | **15.6 min** |
| Build 6 secondary indexes | 1.9 min |
| Verification queries | 3.3 min |
| Restore durable settings | ~0 min |
| **Total** | **21 min** |

Faster than the 20–45 min forecast. The staged approach worked: `LOAD DATA LOCAL INFILE` with
indexes deferred, on a 2 GB buffer pool.

---

## 4.8 What this phase proves

1. Every Phase 2 measurement was reproduced **independently, in a different engine**. Row counts,
   maxima, NULL counts, orphan rates, the base rate and the F1 split-payment count all match. Two
   independent measurements agreeing is much stronger evidence than either alone.
2. The two structural findings (F1 grain, F2 orphans) are now facts in the database, not notes in a
   document.
3. `SOURCE='train'/'test'` (decision **[D5]**) is validated: it eliminated the orphan problem outright.

**Nothing downstream is blocked.** Phase 5 (data-quality assessment) can begin against real SQL.
