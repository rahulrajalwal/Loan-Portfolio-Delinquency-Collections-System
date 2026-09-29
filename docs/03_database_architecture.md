# Phase 3 — Database Architecture & Relational Schema

**Date:** 2026-09-05
**Artifacts:** [`database/schema.sql`](../database/schema.sql) (generated) ·
[`database/generate_schema.py`](../database/generate_schema.py) (generator)

---

## 3.1 Why a relational database at all?

A fair challenge: the data arrives as seven CSVs, and pandas can read them. Why load 58 million rows
into MySQL first?

| Reason | Concretely, here |
|---|---|
| **The data does not fit in memory** | 2.68 GB of CSV expands to roughly 8–10 GB as pandas objects. This machine has 7.3 GB of RAM. MySQL streams from disk and only holds the working set. |
| **The questions are relational** | "For each customer, the DPD trajectory of every active contract, joined to contract terms, weighted by exposure" is four joins across four grains. That is what a join engine is for. |
| **Grain control is enforceable** | Primary keys make grain a *declared, checked* property rather than an assumption. Phase 2's F1 is exactly the failure that PK declaration catches. |
| **Repeatability** | A saved query is auditable and re-runnable. A notebook cell that was run out of order is not. |
| **It is the honest answer for a lending analyst** | Real bank data lives in relational warehouses. Doing this in pandas would dodge the skill the project exists to demonstrate. |

Python still has a role — validation and cross-checking (Phase 11) — but SQL is the analytical engine.

---

## 3.2 The logical model

```mermaid
erDiagram
    APPLICATION ||--o{ BUREAU : "external credits"
    APPLICATION ||--o{ PREVIOUS_APPLICATION : "prior applications"
    BUREAU ||--o{ BUREAU_BALANCE : "monthly status"
    PREVIOUS_APPLICATION ||--o{ POS_CASH_BALANCE : "monthly status"
    PREVIOUS_APPLICATION ||--o{ CREDIT_CARD_BALANCE : "monthly balance"
    PREVIOUS_APPLICATION ||--o{ INSTALLMENTS_PAYMENTS : "payment events"

    APPLICATION {
        mediumint SK_ID_CURR PK
        enum SOURCE
        tinyint TARGET "NULL for test rows"
    }
    BUREAU {
        mediumint SK_ID_BUREAU PK
        mediumint SK_ID_CURR FK
    }
    BUREAU_BALANCE {
        mediumint SK_ID_BUREAU PK-FK
        tinyint MONTHS_BALANCE PK
        char STATUS
    }
    PREVIOUS_APPLICATION {
        mediumint SK_ID_PREV PK
        mediumint SK_ID_CURR FK
    }
    POS_CASH_BALANCE {
        mediumint SK_ID_PREV PK-FK
        tinyint MONTHS_BALANCE PK
        smallint SK_DPD
    }
    CREDIT_CARD_BALANCE {
        mediumint SK_ID_PREV PK-FK
        tinyint MONTHS_BALANCE PK
        decimal AMT_BALANCE
    }
    INSTALLMENTS_PAYMENTS {
        bigint payment_id PK "surrogate"
        mediumint SK_ID_PREV FK
        smallint NUM_INSTALMENT_NUMBER
    }
```

### Table → key → cardinality → purpose

| Table | PK | FK | Cardinality from parent | Analytical purpose |
|---|---|---|---|---|
| `application` | `SK_ID_CURR` | — | — | Borrower dimension + the `TARGET` outcome |
| `bureau` | `SK_ID_BUREAU` | `SK_ID_CURR` | 1 : 0..116 (mean 5.61) | External credit signals |
| `bureau_balance` | (`SK_ID_BUREAU`,`MONTHS_BALANCE`) | `SK_ID_BUREAU` | 1 : 0..97 | External delinquency panel |
| `previous_application` | `SK_ID_PREV` | `SK_ID_CURR` | 1 : 0..77 (mean 4.93) | Contract terms, annuity, origination recency |
| `pos_cash_balance` | (`SK_ID_PREV`,`MONTHS_BALANCE`) | `SK_ID_PREV` | 1 : 0..96 | **Primary DPD panel** |
| `credit_card_balance` | (`SK_ID_PREV`,`MONTHS_BALANCE`) | `SK_ID_PREV` | 1 : 0..96 | Direct exposure + utilisation |
| `installments_payments` | `payment_id` (surrogate) | `SK_ID_PREV` | 1 : 0..many | **Repayment behaviour** |

**Cumulative fan-out from `application`:** 1 → ~4.93 contracts → ~40 payment events. Any query that
touches all three grains without intermediate aggregation multiplies rows ~200×.

---

## 3.3 Physical design decisions

### D5 — `application` unions train and test ✅ adopted

Phase 2 F2 measured **zero** referential orphans against `train ∪ test`, but ~14% against `train`
alone. A single `application` table (356,255 rows) with `SOURCE ENUM('train','test')` and `TARGET`
nullable therefore gives perfect integrity for every child table.

Behavioural history for test customers is fully valid for portfolio and collections analysis; only
the outcome is missing. Module M11 (signal validation) filters `WHERE SOURCE = 'train'`.

### `installments_payments` — surrogate key ✅ adopted

Phase 2 F1 proved no natural key exists: one row is a **payment event**, and 640,905 installments were
settled by two or more payments. Options considered:

| Option | Verdict |
|---|---|
| (`SK_ID_PREV`,`VERSION`,`NUMBER`) | ❌ Not unique — 653,483 duplicate rows |
| Add `DAYS_ENTRY_PAYMENT` to the key | ❌ Still collides on ~0.1% (two payments the same day) |
| **Surrogate `BIGINT AUTO_INCREMENT`** | ✅ Guaranteed unique, cheap, honest about the grain |

Trade-off, stated openly: in InnoDB the PK is the **clustered index**, so a surrogate stores rows in
load order rather than grouped by contract. The secondary index
`ix_inst_prev_num (SK_ID_PREV, NUM_INSTALMENT_NUMBER)` restores efficient access for the aggregation
this table exists to serve. Making that index *covering* is reserved as a **Phase 11 optimisation
demonstration** with before/after timings.

### Foreign key constraints — declared only where they hold

This is the most consequential decision in this phase.

Phase 2 F3 measured **genuine orphans**:

| Relationship | Orphan rate |
|---|---:|
| `pos_cash_balance.SK_ID_PREV` → `previous_application` | 4.00% |
| `credit_card_balance.SK_ID_PREV` → `previous_application` | 10.90% |
| `installments_payments.SK_ID_PREV` → `previous_application` | 3.89% |
| `bureau_balance.SK_ID_BUREAU` → `bureau` | 5.27% |

**Declaring FK constraints on these would cause MySQL to reject real rows at load.** We would lose
genuine behavioural data to satisfy a constraint the source data does not honour.

**Decision:** no FK constraints in `schema.sql`. Relationships are documented logically here,
enforced by discipline in queries, and *verified by explicit validation queries* after load (Phase 5)
so the orphan rates are re-measured in the database rather than assumed from the CSVs.

Secondary benefit: FK checking substantially slows bulk loading, which matters for a 13.6M-row table
on this hardware.

*Counter-argument acknowledged:* a purist would declare FKs and quarantine rejected rows to a
side table. That is defensible, and arguably better practice in a production warehouse. It is
rejected here because the orphans are ~5% of behavioural data and losing them would bias the
portfolio view, not merely shrink it.

### Column types — measured, not assumed

Types come from a full scan of every column ([`generate_schema.py`](../database/generate_schema.py)),
not from guesswork. Highlights:

| Column | Type chosen | Why |
|---|---|---|
| `SK_ID_CURR`, `SK_ID_PREV`, `SK_ID_BUREAU` | `MEDIUMINT UNSIGNED` (3 B) | Max observed 6,843,457 < 16,777,215. `INT` would waste 1 byte × ~58M rows |
| `MONTHS_BALANCE` | `TINYINT` (1 B) | Range −96..0 |
| `STATUS` (bureau_balance) | `CHAR(1)` (1 B) | Single character, 8 levels |
| `SK_DPD`, `SK_DPD_DEF` | `SMALLINT UNSIGNED` | **Max 4,231 — `TINYINT` would silently truncate** |
| `NUM_INSTALMENT_NUMBER` | `SMALLINT UNSIGNED` | **Max 277 — `TINYINT` (255) would silently truncate** |
| `DAYS_EMPLOYED` | `MEDIUMINT` | Only because of the **365243 sentinel** (F8). After cleaning it would fit `SMALLINT` |
| `NAME_CONTRACT_STATUS` | `ENUM(...)` | Stores a 1-byte index instead of up to 21 characters, on 10M and 3.8M row tables |
| all 35 `AMT_*` columns | **`DECIMAL(15,3)` uniformly** | See below |

**Why one type for all money.** The generator initially produced `DECIMAL(9,1)` for `AMT_CREDIT`,
`DECIMAL(11,3)` for `AMT_INSTALMENT` and plain `MEDIUMINT` for `AMT_CREDIT_LIMIT_ACTUAL` — each
technically correct for its own range. But cross-table arithmetic is the whole point of this project:
`AMT_PAYMENT − AMT_INSTALMENT`, `AMT_BALANCE / AMT_CREDIT_LIMIT_ACTUAL`. Mixed scales give
inconsistent rounding at the boundaries. Max observed magnitude is 585,000,000 and max observed scale
is 3, so **`DECIMAL(15,3)`** covers every monetary value with headroom, at a cost of ~2 bytes per
column. Correctness over bytes.

**`DECIMAL`, not `FLOAT`/`DOUBLE`.** Binary floating point cannot represent 0.1 exactly. Summing
13.6M payment amounts in `DOUBLE` accumulates error; in an exposure figure that is indefensible.

### Index strategy — driven by the queries we will actually run

| Index | Serves |
|---|---|
| `pos_cash_balance` PK (`SK_ID_PREV`,`MONTHS_BALANCE`) | Clustered — stores each contract's months **physically adjacent and in order**. This is what makes `LAG(...) OVER (PARTITION BY SK_ID_PREV ORDER BY MONTHS_BALANCE)` cheap, and roll rates (M7) are built entirely on that window |
| `credit_card_balance` PK, same shape | Same, for card panels |
| `ix_pos_curr`, `ix_cc_curr`, `ix_prev_curr`, `ix_bureau_curr` (`SK_ID_CURR`) | Customer-level rollups and joins back to `application` |
| `ix_inst_prev_num` (`SK_ID_PREV`,`NUM_INSTALMENT_NUMBER`) | The F1 aggregation — `SUM(AMT_PAYMENT)` grouped per installment |
| `ix_inst_curr` (`SK_ID_CURR`) | Customer-level repayment aggregates |
| `bureau_balance` PK (`SK_ID_BUREAU`,`MONTHS_BALANCE`) | External roll rates, same window pattern |

No index is created speculatively. Indexes cost disk and slow inserts; each one above maps to a named
module.

**Load-time note:** secondary indexes are added **after** bulk load, not before. Building an index
once over a finished table is far faster than maintaining it across 13.6M inserts.

---

## 3.4 Storage estimate — revised down

Phase 0 estimated 12–17 GB using generic assumptions. With measured types the estimate is far lower:

| Table | Rows | Est. data | Est. index | Est. total |
|---|---:|---:|---:|---:|
| `installments_payments` | 13,605,401 | ~0.83 GB | ~0.30 GB | ~1.13 GB |
| `bureau_balance` | 27,299,925 | ~0.82 GB | — | ~0.82 GB |
| `pos_cash_balance` | 10,001,358 | ~0.40 GB | ~0.15 GB | ~0.55 GB |
| `credit_card_balance` | 3,840,312 | ~0.46 GB | ~0.06 GB | ~0.52 GB |
| `previous_application` | 1,670,214 | ~0.33 GB | ~0.03 GB | ~0.36 GB |
| `bureau` | 1,716,428 | ~0.21 GB | ~0.03 GB | ~0.24 GB |
| `application` | 356,255 | ~0.21 GB | — | ~0.21 GB |
| **Total** | **58,489,893** | | | **~3.8 GB** |

Against 46 GB free, that is comfortable. **This estimate is unverified** — it will be measured against
`information_schema.TABLES` after load in Phase 4, and this table updated with actuals.

The reduction comes almost entirely from type discipline: `MEDIUMINT` over `INT` on IDs, `TINYINT`
for `MONTHS_BALANCE`, `CHAR(1)` for `STATUS`, and `ENUM` for contract status on the two largest
panels.

---

## 3.5 Open items carried forward

| ID | Item | Phase |
|---|---|---|
| D3 | `SK_DPD` primary, `SK_DPD_DEF` as materiality filter — *recommended, unconfirmed* | 5 |
| D2 | Bucket boundaries incl. splitting 90+ into 91–360 / 360+ | 5 |
| D4 | Lateness measured at full settlement vs first payment | 7 |
| — | Re-measure orphan rates in-database and confirm storage actuals | 4–5 |
| — | Covering index on `installments_payments` as an optimisation demo | 11 |
