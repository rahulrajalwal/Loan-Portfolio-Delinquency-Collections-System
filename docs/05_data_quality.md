# Phase 5 — Data Quality Assessment

**Date:** 2026-09-06
**Source:** `sql/01_data_quality/01_quality_assessment.sql` (runtime 541.7s)
**Status:** ✅ Complete. Decisions **[D2]** and **[D3]** resolved on evidence.

---

## 5.1 Decisions resolved

### [D3] — `SK_DPD` is the primary DPD measure

| Source | Delinquent months (`SK_DPD`) | (`SK_DPD_DEF`) | Vanish under DEF | **31–90 bucket: `SK_DPD`** | **`SK_DPD_DEF`** |
|---|---:|---:|---:|---:|---:|
| `pos_cash_balance` | 295,227 | 113,969 | 181,258 (**61.40%**) | **12,940** | **1,152** |
| `credit_card_balance` | 153,355 | 89,340 | 64,015 (**41.74%**) | 6,716 | 1,005 |

`SK_DPD_DEF` removes **91% of the POS middle bucket** (12,940 → 1,152). Roll-rate analysis through
31–90 would rest on a thousand observations across a ten-million-row panel.

**Decision:** `SK_DPD` primary. `SK_DPD_DEF` retained as a **materiality filter** in the collections
module — *"of the accounts we would prioritise, how many remain delinquent once trivial balances are
ignored?"* Both fields used for what each is good at.

### [D2] — Two bucket schemes, because one cannot serve both purposes

The decisive evidence is not account-*months* but **distinct accounts, by the worst bucket they ever
reach** (936,325 POS contracts):

| Worst bucket reached | Accounts | % |
|---|---:|---:|
| Never delinquent | 859,293 | 91.77% |
| Peaked 1–30 | 68,635 | 7.33% |
| Peaked 31–60 | 2,503 | 0.267% |
| **Peaked 61–90** | **542** | **0.058%** |
| Peaked 91–180 | 989 | 0.106% |
| Peaked 181–360 | 1,341 | 0.143% |
| Peaked 360+ | 3,022 | 0.323% |

**Only 542 accounts in the entire book ever peak at 61–90.** A transition rate computed through that
bucket is not a statistic, it is anecdote.

Note the **U-shape**: 2,503 → **542** → 989 → 1,341 → 3,022. The population *falls* into 61–90 and
*rises* again beyond it. 61–90 is a **transit state, not a resting state** — accounts pass through it
quickly and settle in the deep buckets. That is exactly why it is so thinly populated at any
observation point.

**Decision — adopt two schemes, used for different jobs:**

| Scheme | Buckets | Used for | Rationale |
|---|---|---|---|
| **Reporting** (RBI-aligned) | 0 / 1–30 / 31–60 / 61–90 / 91–360 / 360+ | Portfolio reporting, dashboard, regulatory comparability | Maps to SMA-0 / SMA-1 / SMA-2 / NPA. Splitting 90+ at 360 is required — 360+ holds more accounts (3,022) than 91–360 (2,330) and means something operationally different |
| **Analytical** (roll-rate) | 0 / 1–30 / **31–90** / 91–360 / 360+ | Roll-rate matrices, vintage curves | Merges the two sparse middle buckets into one with 3,045 accounts. Every cell still published **with its count** |

This mirrors real practice: banks maintain regulatory classification buckets *and* operational
collections buckets, and they are not the same. Splitting 90+ at 360 days is non-negotiable — an
account at 4,231 DPD is not the same problem as one at 95 DPD.

---

## 5.2 Quality register

| ID | Issue | Table | Column | Severity | Detection | Treatment | Business impact if untreated |
|---|---|---|---|---|---|---|---|
| Q1 | Split payments: 640,905 installments settled by 2+ payments (max **12**), 99.94% fully settled once summed | `installments_payments` | `AMT_PAYMENT` | **Critical** | DQ-02 | `SUM(AMT_PAYMENT)` per installment before comparing to `AMT_INSTALMENT` | Naive row comparison flags **1,295,493 rows (9.52%)** as shortfalls that are fully paid |
| Q2 | Calendar re-versioning adds 743,407 rows; **65 distinct versions, max 178** | `installments_payments` | `NUM_INSTALMENT_VERSION` | High | DQ-03 | Handle separately from Q1; select the applicable version per installment | Double counting of scheduled amounts |
| Q3 | 4.00% of POS contracts have no parent in `previous_application` | `pos_cash_balance` | `SK_ID_PREV` | Medium | DQ-04 | LEFT JOIN; report exposure coverage as 96% | Silent 4% under-count of book exposure |
| Q4 | `DAYS_EMPLOYED = 365243` on 55,374 rows (18.01%) | `application` | `DAYS_EMPLOYED` | **Critical** | DQ-05 | Set NULL, add `FLAG_NOT_EMPLOYED` | +1000-year tenure fed to a group that defaults at **5.40% vs 8.66%** — inverts the conclusion |
| Q5 | 40.30% NULL across five `DAYS_*` columns — **structural, not a defect** | `previous_application` | `DAYS_FIRST_DUE` etc. | High | DQ-06 | Filter to `NAME_CONTRACT_STATUS='Approved'` for schedule analysis | Vintage cohorts polluted by contracts that never disbursed |
| Q6 | 365243 sentinel in date columns (up to 55.95%) | `previous_application` | `DAYS_FIRST_DRAWING` etc. | High | DQ-07 | Set NULL before any date arithmetic | Terminations dated ~1000 years in the future |
| Q7 | Negative debt: 8,418 rows, min −4,705,600 | `bureau` | `AMT_CREDIT_SUM_DEBT` | Medium | DQ-08 | Treat as NULL, not 0 — sign is unexplained | Understates external exposure |
| Q8 | **Debt exceeds facility on 29,642 rows** | `bureau` | `AMT_CREDIT_SUM_DEBT` > `AMT_CREDIT_SUM` | Medium | DQ-08 | Flag; do not silently cap | Utilisation ratios above 100% with no explanation |
| Q9 | Negative card balance: 2,345 rows, min −420,250 | `credit_card_balance` | `AMT_BALANCE` | Low | DQ-08 | Credit balances (overpayment) — legitimate, exclude from exposure | Minor exposure overstatement |
| Q10 | Utilisation > 1.5 on 569 account-months | `credit_card_balance` | `AMT_BALANCE`/`AMT_CREDIT_LIMIT_ACTUAL` | Low | DQ-08 | Cap display at 100%+, report separately | Distorted utilisation averages |
| Q11 | 392 payments recorded >1 year before due date | `installments_payments` | `DAYS_ENTRY_PAYMENT` | Low | DQ-08 | Flag and exclude from lateness stats (0.0029%) | Negligible, but skews min/max |
| Q12 | **`NAME_CASH_LOAN_PURPOSE` is 95.8% placeholder** (1,600,579 of 1,670,214 are XNA/XAP) | `previous_application` | `NAME_CASH_LOAN_PURPOSE` | High | DQ-09 | **Unusable as a dimension** | A "loan purpose" chart whose largest bar is meaningless |
| Q13 | `NAME_PRODUCT_TYPE` 63.7% XNA; `NAME_YIELD_GROUP` 31.0%; `NAME_PORTFOLIO` 22.3%; `ORGANIZATION_TYPE` 21.0% | `previous_application`, `application` | various | Medium | DQ-09 | Report XNA as an explicit category, never drop silently | Misleading segment comparisons |
| Q14 | `AMT_INCOME_TOTAL` max 117,000,000 vs mean 168,798; 3 rows >10M, 44 >2M | `application` | `AMT_INCOME_TOTAL` | Medium | DQ-10 | Use median for reporting; winsorise for banding | One row moves a segment mean |
| Q15 | `bureau_balance.STATUS='X'` unknown on 5,810,482 rows (21.28%) | `bureau_balance` | `STATUS` | **High** | DQ-11 | Exclude explicitly from delinquency numerators AND denominators | Treating X as current understates external delinquency across a fifth of history |
| Q16 | Coverage is partial across every behavioural table | all | — | High | DQ-12 | Scope every metric to its stated population | "Delinquency rate" without a denominator is meaningless |
| Q17 | **Missingness of `EXT_SOURCE` is informative, not random** | `application` | `EXT_SOURCE_1`, `_3` | **High** | DQ-15 | Never mean-fill. Use a `missing` flag as a signal in its own right | Destroys a real predictive signal and biases the sample |

---

## 5.3 Findings that changed the plan

### Q5 — the 40.30% NULL mystery is fully solved

| `NAME_CONTRACT_STATUS` | Rows | NULL `DAYS_FIRST_DUE` | % |
|---|---:|---:|---:|
| Approved | 1,036,781 | 39,632 | **3.82%** |
| Canceled | 316,319 | 316,319 | **100.00%** |
| Refused | 290,678 | 290,678 | **100.00%** |
| Unused offer | 26,436 | 26,436 | **100.00%** |

633,433 non-approved + 39,632 approved = 673,065 = **exactly 40.30%**.

**A contract that was never disbursed has no payment schedule.** The NULLs are not a defect — they
are the correct representation of an absent fact. Treatment is to *filter*, never to impute.

The residual **39,632 approved contracts with no schedule (3.82%)** is a genuine anomaly and is
carried into the limitation register.

### Q17 — missing external scores predict default

| Group | Rows | `TARGET` rate |
|---|---:|---:|
| `EXT_SOURCE_1` present | 134,133 | 7.4955% |
| `EXT_SOURCE_1` **missing** | 173,378 | **8.5195%** |
| `EXT_SOURCE_3` present | 246,546 | 7.7665% |
| `EXT_SOURCE_3` **missing** | 60,965 | **9.3119%** |

Missing `EXT_SOURCE_3` carries a **20% higher relative default rate**. Missingness is a signal, not a
gap to be patched. Mean-filling would erase it and bias the sample simultaneously.

**Consequence for Phase 9:** `EXT_SOURCE_x IS NULL` becomes a candidate early-warning flag in its own
right — with the honest caveat that we do not know *why* the score is absent (thin file, bureau
non-match, or a process gap), so this is association, not mechanism.

### Q1 — the cost of the naive comparison, measured

Comparing `AMT_PAYMENT < AMT_INSTALMENT` row by row flags **1,295,493 rows (9.52%)** as
underpayments. Aggregating first shows **99.94% of those installments were paid in full**. One
installment was settled across **12 separate payments**.

### DQ-05 refinement

Earlier (pandas) I stated 100% of sentinel rows have NULL `OCCUPATION_TYPE`. Measured in SQL:
**55,372 of 55,374 (99.9964%)**. Two rows carry an occupation despite the sentinel. Immaterial, but
recorded for accuracy.

Also surfaced: `Unemployed` (n=22) defaults at **36.36%** and `Maternity leave` (n=5) at 40% — the
highest rates in the book, on populations far too small to act on. A reminder to publish counts
beside every rate.

### Payment timing, full distribution

| Band | Rows | % |
|---|---:|---:|
| Paid early | 9,309,085 | 68.44% |
| Paid on due date | 3,146,350 | 23.13% |
| Late 1–30 | 1,108,027 | 8.15% |
| Late 31–90 | 25,904 | 0.190% |
| Late 90+ | 12,738 | 0.094% |
| Paid >1yr early (suspect) | 392 | 0.0029% |

**91.57% arrive early or on time.** Severe lateness is 0.094%. Any Phase 9 signal built on lateness
must be calibrated against that, not against an assumption that missed payments are common.

### Coverage (Q16) — the denominators every metric must state

| Population | Customers | % of 356,255 |
|---|---:|---:|
| Total (train + test) | 356,255 | 100% |
| With installment history | 339,587 | 95.3% |
| With any previous application | 338,857 | 95.1% |
| With POS/cash history | 337,252 | 94.7% |
| With bureau credit | 305,811 | 85.8% |
| **With credit-card history** | **103,558** | **29.1%** |

Bureau credits with monthly history: **774,354 of 1,716,428 = 45.11%**.

---

## 5.4 Treatment plan for Phase 6+

A cleaning layer will be built as **views**, not by mutating base tables — the raw load stays
byte-faithful to the source and every transformation is inspectable.

1. `v_application` — `DAYS_EMPLOYED` sentinel → NULL + `FLAG_NOT_EMPLOYED`; XNA/Unknown → explicit
   'Unknown' category; `EXT_SOURCE_x_MISSING` flags.
2. `v_previous_application` — 365243 → NULL across all five `DAYS_*`; `IS_DISBURSED` flag.
3. `v_installments` — aggregated to installment grain: `SUM(AMT_PAYMENT)`, settlement date, days-late
   at full settlement **[D4]**.
4. `v_account_month` — unified POS + card panel with both bucket schemes and an exposure column
   (direct for cards, proxy for POS, flagged as such).
5. `v_bureau_balance` — `STATUS='X'` excluded explicitly with the exclusion counted, not dropped.

**[D4] still open** (Phase 7): lateness measured at first payment vs full settlement.
