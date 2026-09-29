# Phase 2 — Dataset Inspection, Grain & Referential Integrity

**Date:** 2026-09-04
**Status:** ✅ Complete — Run 1 (keys, grain, integrity, fan-out), Run 2 (nulls, dtypes,
categoricals — see `_phase2_column_profile.md`), Run 3 (DPD distribution, sentinels, invalid values).

All figures below are **measured on `data/raw/`**, not quoted from documentation.

---

## 2.1 Primary key / grain tests

| Table | Claimed key | Rows | Distinct keys | Duplicate rows | Verdict |
|---|---|---:|---:|---:|---|
| `application_train` | (`SK_ID_CURR`) | 307,511 | 307,511 | 0 | ✅ unique |
| `bureau` | (`SK_ID_BUREAU`) | 1,716,428 | 1,716,428 | 0 | ✅ unique |
| `bureau_balance` | (`SK_ID_BUREAU`,`MONTHS_BALANCE`) | 27,299,925 | 27,299,925 | 0 | ✅ unique |
| `previous_application` | (`SK_ID_PREV`) | 1,670,214 | 1,670,214 | 0 | ✅ unique |
| `POS_CASH_balance` | (`SK_ID_PREV`,`MONTHS_BALANCE`) | 10,001,358 | 10,001,358 | 0 | ✅ unique |
| `credit_card_balance` | (`SK_ID_PREV`,`MONTHS_BALANCE`) | 3,840,312 | 3,840,312 | 0 | ✅ unique |
| `installments_payments` | (`SK_ID_PREV`,`NUM_INSTALMENT_VERSION`,`NUM_INSTALMENT_NUMBER`) | 13,605,401 | 12,951,918 | **653,483** | ❌ **NOT UNIQUE** |

Six of seven tables behave exactly as assumed in Phase 0. The seventh does not.

---

## 2.2 ⚠️ Finding F1 — `installments_payments` grain was wrong

**Phase 0 stated:** *"one row = one installment of one previous credit."*
**That is incorrect.** The correct grain is:

> **One row = one PAYMENT EVENT against an installment.**

### Evidence

| Test | Result |
|---|---|
| Rows involved in duplicate keys | **1,294,388 (9.51%)** across 640,905 distinct keys |
| Exact full-row duplicates | **0** — so these are not data errors |
| Keys where `AMT_INSTALMENT` differs across rows | **0 (0.0%)** — same installment, same amount due |
| Keys where `AMT_PAYMENT` differs | 638,836 (**99.7%**) |
| Keys where `DAYS_ENTRY_PAYMENT` differs | 640,238 (**99.9%**) |
| Keys where `SUM(AMT_PAYMENT) = AMT_INSTALMENT` | **99.9%** |

### Worked example

`SK_ID_PREV = 2270983`, installment number 30, due on day −2022, amount due 9,000:

| Row | `DAYS_ENTRY_PAYMENT` | `AMT_PAYMENT` | Timing |
|---|---:|---:|---|
| 1 | −2046 | 1,800 | 24 days **early** |
| 2 | −2019 | 7,200 | 3 days **late** |
| | | **9,000 = exactly the amount due** | |

One installment, settled by two separate payments.

### Consequences — these change how the repayment module must be written

1. **`AMT_PAYMENT` must be aggregated (`SUM`) per installment before comparing to `AMT_INSTALMENT`.**
   Comparing row-by-row would falsely flag roughly 640,000 fully-paid installments as underpaid.
2. **"Days late" becomes a definitional choice, not a calculation.** In the example above, the first
   payment arrived 24 days early and the last arrived 3 days late. Is that installment late?
   - *First-payment definition* → 24 days early
   - *Full-settlement definition* → 3 days late
   **[DECISION D4 — Phase 7]** Proposed: an installment is settled when cumulative payment first
   reaches the amount due, so lateness is measured at **full settlement**. Rationale: a lender is not
   made whole by a partial payment, and it matches how DPD itself works (see A3 — DPD counts from the
   oldest *unpaid* amount).
3. **This table has no natural primary key** as loaded. In MySQL it will be given a surrogate
   `AUTO_INCREMENT` key, with an index on (`SK_ID_PREV`,`NUM_INSTALMENT_NUMBER`) for aggregation.

### Separately: `NUM_INSTALMENT_VERSION` adds rows too

Distinct (`SK_ID_PREV`,`NUM_INSTALMENT_NUMBER`) = 12,861,994, so **743,407 rows (5.46%)** exist
because the payment calendar was re-versioned. Home Credit's own dictionary confirms: *"Change of
installment version from month to month signifies that some parameter of payment calendar has
changed."* Version values observed: 0–11+ (0 = credit card).

This is a **second, independent** source of row multiplication and must be handled separately from
the split-payment effect.

---

## 2.3 Referential integrity

### Application population

| Set | Distinct `SK_ID_CURR` |
|---|---:|
| `application_train` | 307,511 |
| `application_test` | 48,744 |
| Union | 356,255 |
| Overlap | **0** — the two files are disjoint |

### Child → application

| Child table | Distinct `SK_ID_CURR` | Not in `train` | Not in `train ∪ test` |
|---|---:|---:|---:|
| `bureau` | 305,811 | 42,320 (13.84%) | **0 (0.00%)** |
| `previous_application` | 338,857 | 47,800 (14.11%) | **0 (0.00%)** |
| `POS_CASH_balance` | 337,252 | 47,808 (14.18%) | — |
| `credit_card_balance` | 103,558 | 16,653 (16.08%) | — |
| `installments_payments` | 339,587 | 47,944 (14.12%) | — |

**Finding F2 — the ~14% "orphans" are not orphans.** They are `application_test` customers. Against
the full application population the referential integrity is **perfect (0 orphans)**.

**[DECISION D5 — Phase 3]** This forces a choice: load `application_test` as part of the application
dimension, or accept that ~14% of every child table has no matching application row. Proposed: **load
both**, with a `SOURCE` flag ('train'/'test'), because the behavioural history of test customers is
perfectly valid for portfolio and collections analysis — only the `TARGET` outcome is missing. The
early-warning *validation* module (M11) then restricts to `SOURCE='train'`, where the outcome exists.

### Child → parent contract

| Child table | Distinct `SK_ID_PREV` | Not in `previous_application` |
|---|---:|---:|
| `POS_CASH_balance` | 936,325 | **37,422 (4.00%)** |
| `credit_card_balance` | 104,307 | **11,372 (10.90%)** |
| `installments_payments` | 997,752 | **38,847 (3.89%)** |
| `bureau_balance` → `bureau` (`SK_ID_BUREAU`) | 817,395 | **43,041 (5.27%)** |

**Finding F3 — these are genuine orphans.** Unlike F2, there is no second parent file to rescue them.
Behavioural records exist for contracts that do not appear in `previous_application`. Impact: any
metric requiring `AMT_ANNUITY` from `previous_application` — notably the **POS/cash exposure proxy**
(A2) — is unavailable for ~4% of POS contracts and ~11% of card contracts. This must be quantified in
Phase 5 and disclosed, not silently dropped by an inner join.

**Finding F4 — coverage is partial by design.**
- Only **817,395 of 1,716,428** bureau credits (47.6%) have any monthly history in `bureau_balance`.
- Only **103,558** customers (33.7% of `application_train`) have any credit-card record — cards are a
  minority product in this book.
- `POS_CASH_balance` covers 936,325 of 1,670,214 prior contracts (56.1%).

Portfolio statements must therefore be scoped to the covered population, never presented as
whole-book figures.

---

## 2.4 Fan-out factors — measured

Children per `SK_ID_CURR`:

| Child table | Mean | Median | p95 | Max |
|---|---:|---:|---:|---:|
| `bureau` | 5.61 | 4 | 14 | 116 |
| `previous_application` | 4.93 | 4 | 13 | 77 |
| `POS_CASH_balance` | 29.66 | 22 | 80 | 295 |
| `credit_card_balance` | 37.08 | 22 | 96 | 192 |
| `installments_payments` | **40.06** | 25 | 131 | **372** |

**The Phase 0 quiz answer, now measured:** joining `application_train` to `installments_payments` on
`SK_ID_CURR` and summing `AMT_CREDIT` inflates the total by roughly **40×** on average — and by up to
**372×** for the worst-affected customer. Because the multiplier varies per customer, the error is not
even a constant factor you could divide out; it silently re-weights the entire portfolio toward
customers with long payment histories.

**Rule adopted for the whole project:** aggregate the child table to the parent's grain **first**,
then join. Every multi-table query gets a row-count reconciliation before its result is trusted.

---

## 2.5 DPD distribution — the evidence for decision D2

### `POS_CASH_balance` — 10,001,358 account-months

| Bucket | `SK_DPD` rows | % of all months | `SK_DPD_DEF` rows | % |
|---|---:|---:|---:|---:|
| 0 (current) | 9,706,131 | 97.0481% | 9,887,389 | 98.8605% |
| 1–30 | 163,169 | 1.6315% | 108,135 | 1.0812% |
| **31–60** | **7,944** | **0.0794%** | 871 | 0.0087% |
| **61–90** | **4,996** | **0.0500%** | 281 | 0.0028% |
| 91–180 | 12,537 | 0.1254% | 351 | 0.0035% |
| 181–360 | 18,988 | 0.1899% | 469 | 0.0047% |
| **360+** | **87,593** | **0.8758%** | 3,862 | 0.0386% |

Non-zero `SK_DPD` percentiles: p10=2, p25=5, **p50=19, p75=528**, p90=1407, p95=1956, p99=2801.
Max = **4,231 days (11.6 years)**.

### `credit_card_balance` — 3,840,312 account-months

| Bucket | `SK_DPD` rows | % |
|---|---:|---:|
| 0 | 3,686,957 | 96.0067% |
| 1–30 | 98,413 | 2.5626% |
| 31–60 | 4,474 | 0.1165% |
| 61–90 | 2,242 | 0.0584% |
| 91–180 | 5,083 | 0.1324% |
| 181–360 | 8,230 | 0.2143% |
| 360+ | 34,913 | 0.9091% |

Among **Active** months only: `SK_DPD > 0` in **3.07%** (POS) and **4.11%** (cards).

### Finding F6 — the DPD distribution is bimodal, and the middle buckets are nearly empty

The jump from p50 = 19 days to p75 = 528 days shows two separate populations: a large cluster of
mild, curable lateness (1–30), and a large cluster of long-dead accounts. The **31–60 and 61–90
buckets together hold only 0.13% of account-months** — 12,940 rows out of 10 million.

Meanwhile **360+ alone holds 0.88%** — 74% of everything at 90+ DPD. With a maximum of 4,231 days,
these are effectively written-off accounts whose DPD counter kept running.

**Consequences:**
1. **[D2] recommendation, now evidence-based:** keep the RBI-aligned grid (0 / 1–30 / 31–60 / 61–90)
   for comparability, but **split 90+ into `91–360` and `360+ (long-term / presumed written off)`**.
   An account at 4,231 DPD is not operationally the same problem as one at 95 DPD, and merging them
   would put ~74% of the "90+" bucket's mass into accounts no collections team would ever work.
2. **Roll-rate matrices will have thin cells.** Transitions through 31–60 and 61–90 are computed on
   thousands, not millions, of observations. Every roll-rate table must publish **cell counts
   alongside rates**, and we must not quote a transition percentage derived from a few hundred
   accounts as though it were stable.

### Finding F7 — `SK_DPD` vs `SK_DPD_DEF` changes delinquency by a factor of ~2.5

| Table | Rows differ | Delinquent on `SK_DPD` but **not** on `SK_DPD_DEF` |
|---|---:|---:|
| `POS_CASH_balance` | 183,880 (1.84%) | 181,258 — **61.4%** of all `SK_DPD > 0` |
| `credit_card_balance` | 64,439 (1.68%) | 64,015 — **41.7%** of all `SK_DPD > 0` |

`SK_DPD_DEF` non-zero medians collapse to 4 days (POS) and 1 day (cards) — it is stripping out
trivial-amount lateness, exactly as the dictionary says.

**[D3] recommendation:** use **`SK_DPD` as the primary measure**, because `SK_DPD_DEF` empties the
31–60 and 61–90 buckets almost entirely (871 and 281 rows) and would make roll-rate analysis
impossible. Report `SK_DPD_DEF` as a **materiality filter** in the collections module — i.e. "of the
accounts we would prioritise, how many are still delinquent once trivial balances are ignored?" That
is a genuinely useful second view, and it uses both fields for what each is good for.

---

## 2.6 Sentinels, invalid values and base rates

### Base rate
**`TARGET` = 8.0729%** (24,825 of 307,511). This is the benchmark every early-warning signal in M11
must be measured against.

### Finding F8 — `DAYS_EMPLOYED = 365243` fully explained

55,374 rows (18.01%) carry the value 365243 — which decodes to employment starting ~1,000 years in
the **future**. Cross-tabulation identifies it precisely:

| `NAME_INCOME_TYPE` | Sentinel rows | Group size | % of group |
|---|---:|---:|---:|
| Pensioner | 55,352 | 55,362 | **99.98%** |
| Unemployed | 22 | 22 | **100.00%** |
| Working / Commercial associate / State servant / Student / Businessman / Maternity leave | **0** | 251,127 | **0.00%** |

Also: **100% of sentinel rows have NULL `OCCUPATION_TYPE`** versus 16.27% of non-sentinel rows.

**Verdict:** not corrupt data — an encoding convention meaning "not currently employed".
**Treatment:** set to NULL and carry a `FLAG_NOT_EMPLOYED` derived column.

**Why it matters concretely:** this group's `TARGET` rate is **5.40%** versus **8.66%** for everyone
else. Left untreated, a +1,000-year employment value would be fed into any tenure-based analysis for
a group that is actually *lower* risk than average — inverting the conclusion.

### Other sentinels and invalid values

| Table | Column | Issue | Count | % |
|---|---|---|---:|---:|
| `previous_application` | `DAYS_FIRST_DRAWING` | = 365243 | 934,444 | 55.95% |
| `previous_application` | `DAYS_TERMINATION` | = 365243 | 225,913 | 13.53% |
| `previous_application` | `DAYS_LAST_DUE` | = 365243 | 211,221 | 12.65% |
| `previous_application` | `DAYS_LAST_DUE_1ST_VERSION` | = 365243 | 93,864 | 5.62% |
| `previous_application` | `DAYS_FIRST_DUE` | = 365243 | 40,645 | 2.43% |
| `previous_application` | all five `DAYS_*` | NULL | — | **40.30% each** (identical rate → systematic, investigate in Phase 5) |
| `previous_application` | `RATE_INTEREST_PRIMARY` / `_PRIVILEGED` | NULL | 1,664,263 | **99.644%** (only 5,951 usable) |
| `previous_application` | `SELLERPLACE_AREA` | negative | 762,675 | 45.66% |
| `bureau` | `AMT_CREDIT_SUM_DEBT` | **negative debt** (min −4,705,600) | 8,418 | 0.490% |
| `application_train` | `AMT_INCOME_TOTAL` | max 117,000,000 vs p99 472,500 — **247× p99** | 1 | outlier |
| `application_train` | `CODE_GENDER` | = 'XNA' | 4 | — |
| `application_train` | `NAME_FAMILY_STATUS` | = 'Unknown' | 2 | — |
| `application_train` | `EXT_SOURCE_1` / `_3` / `_2` | NULL | — | 56.38% / 19.83% / 0.21% |
| `application_train` | 41 building/apartment columns | NULL | — | **>50%** (up to 70%) |
| `installments_payments` | `DAYS_ENTRY_PAYMENT`, `AMT_PAYMENT` | NULL (unpaid) | 2,905 | 0.021% |

**F9 — `RATE_INTEREST_PRIMARY` is unusable.** 99.644% null confirms the Phase 0 assessment; only
`NAME_YIELD_GROUP` (a coarse band) supports any yield analysis.

### Finding F10 — payment timing is much healthier than expected

`DAYS_ENTRY_PAYMENT − DAYS_INSTALMENT` across 13,605,401 payment events:

| Outcome | Rows | % |
|---|---:|---:|
| Paid early or on time (≤ 0) | 12,455,827 | **91.55%** |
| Paid late (> 0) | 1,146,669 | 8.43% |
| Late by more than 30 days | 38,642 | **0.284%** |

**Median = −6 days** — the typical payment arrives *six days early*. Range −3,189 to +2,884; the
−3,189 extreme (8.7 years early) is implausible and is flagged for Phase 5.

This reframes the repayment module: severe lateness is **rare**, so any early-warning signal built on
"late payments" must be calibrated against a 0.284% base rate, not an assumed-common event.

### `bureau_balance.STATUS` distribution (27,299,925 rows)

| STATUS | Meaning | Rows | % |
|---|---|---:|---:|
| C | Closed | 13,646,993 | 49.99% |
| 0 | No DPD | 7,499,507 | 27.47% |
| **X** | **Unknown** | **5,810,482** | **21.28%** |
| 1 | 1–30 DPD | 242,347 | 0.89% |
| 5 | 120+ / written off | 62,406 | 0.23% |
| 2 | 31–60 | 23,419 | 0.09% |
| 3 | 61–90 | 8,924 | 0.03% |
| 4 | 91–120 | 5,847 | 0.02% |

**F11 — `X` (unknown) is 21.28% of all bureau-balance months** and must be handled explicitly, never
silently treated as "current". Note also that **status 5 exceeds statuses 2+3+4 combined** — the same
absorbing-state pattern seen in F6.

---

## 2.7 Findings register (running)

| ID | Finding | Severity | Affects | Action |
|---|---|---|---|---|
| F1 | `installments_payments` grain is payment-event, not installment; 9.51% of rows share a key | **High** | M4 repayment behaviour | Aggregate before comparing; define lateness at full settlement [D4] |
| F2 | ~14% child "orphans" are `application_test` customers; integrity is perfect against train ∪ test | **High** | M1, M3 data model | Load both application files with a `SOURCE` flag [D5] |
| F3 | Genuine `SK_ID_PREV` orphans: 4.0% POS, 10.9% card, 3.9% installments; 5.3% `bureau_balance` | Medium | Exposure proxy, joins | Quantify in Phase 5, use LEFT JOIN, disclose |
| F4 | Coverage is partial: 47.6% of bureau credits have history; cards cover only 33.7% of customers | Medium | All portfolio metrics | Scope every statement to the covered population |
| F5 | `NUM_INSTALMENT_VERSION` adds 5.46% extra rows via calendar re-versioning | Medium | M4 | Handle separately from split payments |
| F6 | DPD is bimodal; 31–60 and 61–90 hold only 0.13% of months while 360+ holds 0.88% (max 4,231 days) | **High** | M5, M7 bucket design | Split 90+ into 91–360 and 360+; publish cell counts with every roll rate |
| F7 | `SK_DPD_DEF` removes 61.4% of POS delinquency events and empties the middle buckets | **High** | M5, M12 | `SK_DPD` primary; `SK_DPD_DEF` as a materiality filter in collections |
| F8 | `DAYS_EMPLOYED = 365243` on 18.01% of rows = pensioners (99.98%) + unemployed (100%) | **High** | M1, M10 | NULL it, add `FLAG_NOT_EMPLOYED`; group defaults at 5.40% vs 8.66% |
| F9 | `RATE_INTEREST_PRIMARY`/`_PRIVILEGED` 99.644% null | Medium | Yield analysis | Drop; use `NAME_YIELD_GROUP` band only |
| F10 | 91.55% of payments arrive early/on time; only 0.284% are >30 days late; median −6 days | **High** | M4, M10 | Calibrate late-payment signals against a 0.284% base rate |
| F11 | `bureau_balance.STATUS = 'X'` (unknown) is 21.28% of months | **High** | M7 external roll rate | Handle explicitly; never treat as current |
| F12 | 5 × `DAYS_*` in `previous_application` share an identical 40.30% null rate | Medium | M8 vintage | Systematic — investigate cause in Phase 5 |
| F13 | `bureau.AMT_CREDIT_SUM_DEBT` negative on 8,418 rows (min −4,705,600) | Medium | Exposure | Impossible value; treat in Phase 5 |

---

## 2.6 Open decisions raised in this phase

- **[D4 — Phase 7]** Lateness measured at **full settlement** vs first payment. *Proposed: full settlement.*
- **[D5 — Phase 3]** Load `application_test` into the application dimension with a `SOURCE` flag.
  *Proposed: yes.*
