# Dataset & Scope Re-evaluation

**Date:** 2026-09-07 · **Trigger:** Rahul's request to re-evaluate before continuing Phase 6
**Status:** Analysis complete — awaiting decision

---

## 1. Current dataset summary

Home Credit Default Risk, loaded and verified in MySQL 8.0:

| Table | Rows | Grain |
|---|---:|---|
| `application` | 356,255 | one loan application (train 307,511 + test 48,744) |
| `bureau` | 1,716,428 | one external credit |
| `bureau_balance` | 27,299,925 | one month of one external credit |
| `previous_application` | 1,670,214 | one prior internal contract |
| `pos_cash_balance` | 10,001,358 | one month of a POS/cash account |
| `credit_card_balance` | 3,840,312 | one month of a card account |
| `installments_payments` | 13,605,401 | one **payment event** (F1) |
| **Total** | **58,441,594** | |

Plus a staged layer: `stg_installment` (12,951,918), `stg_account_month` (13,841,670),
`stg_book` (1,040,632).

**Storage: 5.86 GB** (+ ~2 GB staging).

---

## 2. Is it too large? — measured, not asserted

### 2a. Query latency

| Query | Rows | Time |
|---|---:|---:|
| Delinquency by bucket | 13.8M | 16.7s |
| Book snapshot | 13.8M | 48.4s |
| `bureau_balance` full scan | 27.3M | 73.5s |
| Customer-level repayment aggregate | 12.9M | **115.5s** |
| **Roll-rate `LAG` over panel** | 13.8M | **275.7s** |

### 2b. Is the roll-rate cost fixable? — **No.**

Hypothesis tested: the `LAG` partitions by `SK_ID_PREV` while the PK is
`(SK_ID_PREV, PRODUCT, MONTHS_BALANCE)`, so maybe MySQL is sorting unnecessarily.

```
-> Window aggregate with buffering: lag(...) OVER (PARTITION BY SK_ID_PREV ORDER BY MONTHS_BALANCE)
    -> Sort: SK_ID_PREV, MONTHS_BALANCE  (cost=1.43e+6 rows=13.2e+6)
        -> Index scan on stg_account_month using ix_am_bucket
```

Aligning the partition to the PK prefix changes nothing: **253.4s vs 271.9s**, and both plans still
perform a full sort of 13.2M rows. MySQL 8 always materialises and sorts for buffered window
functions; it does not use clustered-index order to avoid the sort.

**Conclusion: the ~4.5-minute cost of every temporal query is inherent to MySQL at this scale and
cannot be optimised away.** Every roll-rate, deterioration-signal and vintage iteration costs minutes.

### 2c. The decisive number — input size vs analytical output

| Stage | Rows |
|---|---:|
| Loaded | **58,441,594** |
| → accounts at their latest observed month | 1,040,632 |
| → **Active** accounts (the live book) | **327,101** |
| → delinquent in the live book | **7,211** |
| → 30+ DPD | **2,048** |
| → 90+ DPD | **1,676** |

**58.4 million rows produce a collections queue of roughly 2,000 accounts.**

Why: only 31.4% of accounts are Active at their last observation. Accounts that deteriorate badly get
Completed or closed, so the surviving active set is disproportionately healthy.

The live book by bucket:

| Product | Bucket | Accounts | Exposure (M) |
|---|---|---:|---:|
| POS | 0-current | 230,255 | 43,952.8 |
| POS | 1–30 | 4,646 | 376.0 |
| POS | 31–90 | 325 | 98.3 |
| POS | 91–360 | 209 | 17.1 |
| POS | 360+ | 714 | 0.1 |
| CARD | 0-current | 89,635 | 7,680.2 |
| CARD | 1–30 | 517 | 89.6 |
| CARD | 31–90 | **47** | 2.9 |
| CARD | 91–360 | 98 | 1.1 |
| CARD | 360+ | 655 | 0.1 |

**Rahul's instinct is correct.** The dataset is heavily oversized relative to what it produces. The
58M rows are *input* for computing behavioural features; the analytical outputs are all small.

---

## 3. India-first search — round 2 (fresh criteria)

The criteria changed: small size is now an *advantage*. That could have changed the verdict. It did not.

| Source | Finding |
|---|---|
| RBI (BSR-1, DBIE/CIMS, Sectoral Deployment, FSR) | Aggregated at publication. Confirmed again. |
| RBI Public Credit Registry | Still not publicly released |
| data.gov.in / Dataful / India Data Portal | Block/state/year aggregates only (e.g. NRLM SHG loans at *block* level) |
| **Large Indian MFI borrower panel** — 2,036,108 borrowers, full repayment records Jul 2016–Feb 2017, used in a *Strategic Management Journal* demonetization study | **Proprietary, under NDA** |
| Kaleidofin / IIT Madras M.Tech (2022) | **Proprietary**, corporate collaboration |
| ISB — public-sector-bank farmer account data (~25,000 farmers) | **Proprietary**, research access |
| LTFS vehicle loan (Analytics Vidhya) | Real, Indian, ~233k rows — but **one flat table**, first-EMI default only |
| Kaggle "Indian" loan uploads | Tiny, name-lists, or provenance unverifiable |

**Three independent confirmations of the same pattern:** India *has* borrower-level lending data;
it reaches analysts only through institutional agreements; it is never published. This is a
statutory and privacy outcome (CICRA 2005, data-localisation rules, no PCR legislation), not a
search failure.

**LTFS re-evaluated under the new criteria:** its size was never the objection — its *structure* was.
One flat table with a first-EMI flag still supports 1 of 13 modules. Verdict unchanged.

---

## 4. Smaller real alternatives evaluated

| Candidate | Scale | Structure | Verdict |
|---|---|---|---|
| **PKDD'99 / Berka** (Czech bank, 1993–98) | 4,500 accounts, 5,369 clients, **1,056,320 transactions**, **682 loans**, 77 districts w/ demographics | **8 real relational tables**, real calendar dates, real geography | **Rejected on outcome count.** 682 loans, ~76 bad. Best relational teaching set available and it has what Home Credit lacks (calendar dates, geography) — but a "portfolio & collections" project cannot rest on 682 loans and 76 defaults. Segment analysis would have single-digit cells. |
| **Freddie Mac Single-Family (sample)** | 50,000 loans/year, ~2–3M monthly performance rows per vintage year | 2 tables: origination + monthly performance | **Viable but a bad trade.** Gains real calendar vintages and a textbook DPD ladder. Loses 4-level grain, fan-out teaching, borrower richness, the `TARGET` validation design, and every Phase 2–5 finding. Trades a HIGH-priority strength (relational modelling) for a MEDIUM-priority one (calendar vintage). Requires registration. |
| **Lending Club (single year slice)** | ~100–400k loans/year | 1 flat table | Real calendar dates and vintages, but no panel → no roll rates, no repayment behaviour, no relational work |
| **Home Credit — card-only scope** | 104,307 accounts, 3.84M months | Real exposure, real utilisation, no proxy | **Tested and rejected.** Only **47 accounts** in the 31–90 bucket at the snapshot. Collections module collapses. |

---

## 5. Data-sufficiency matrix — modules vs candidates

| # | Module | Importance | Home Credit (full) | Home Credit + mart | Freddie Mac sample | Berka | LTFS |
|---|---|---|---|---|---|---|---|
| M1 | Portfolio composition & exposure | HIGH | ✅ | ✅ | ✅ | ◐ 682 loans | ◐ origination only |
| M2 | Data-quality forensics | HIGH | ✅ (13 findings) | ✅ | ◐ | ◐ | ◐ |
| M3 | Relational model, grain, fan-out | HIGH | ✅ 4 grains | ✅ | ✖ 2 tables | ✅ 8 tables | ✖ 1 table |
| M4 | Repayment behaviour (installment grain) | HIGH | ✅ | ✅ | ✖ | ◐ from transactions | ✖ |
| M5 | Delinquency / DPD | HIGH | ✅ | ✅ | ✅ | ◐ 4-state only | ✖ |
| M6 | Delinquency by segment | HIGH | ✅ | ✅ | ◐ thin attributes | ✖ tiny cells | ◐ |
| M7 | Roll rate | MEDIUM | ✅ but 4.5 min/query | ✅ fast | ✅ | ✖ | ✖ |
| M8 | Vintage / MOB | MEDIUM | ✅ relative time only | ✅ | ✅ **calendar** | ✅ calendar | ✖ |
| M9 | Cohort comparison | MEDIUM | ✅ relative | ✅ | ✅ | ◐ | ✖ |
| M10 | Early-warning framework | HIGH | ✅ | ✅ | ◐ | ◐ | ◐ |
| M11 | **Validation against observed outcome** | HIGH | ✅ `TARGET`, 8.07% base | ✅ | ◐ default flag | ◐ 76 bad loans | ✅ |
| M12 | Collections prioritisation | HIGH | ◐ **7,211 accounts** | ◐ same | ✅ | ✖ | ✖ |
| M13 | Power BI decision layer | HIGH | ✅ | ✅ | ✅ | ◐ | ◐ |
| — | Geography | dropped | ✖ none | ✖ | ✅ US states | ✅ 77 districts | ✅ Indian states |
| | **Fully supported** | | **11/13** | **11/13** | 8/13 | 3/13 | 1/13 |

---

## 5b. Round-3 search — a systematic hunt for a *naturally smaller relational* dataset

Rahul asked for one more pass before committing, specifically for a smaller **real** dataset that
preserves relational structure rather than slimming Home Credit.

### Method
16 search terms run against the Kaggle catalogue via API (loan repayment history, credit risk
loans/customers, bank loans accounts transactions, loan portfolio delinquency, microfinance
repayments, consumer credit panel, mortgage performance loan level, credit bureau accounts, debt
collection accounts, loan default monthly performance, India loan borrower repayment, EMI payment
history, …). 89 unique datasets scanned; every plausible candidate had its **actual file manifest**
inspected to count real data tables.

### Result — only five had 3+ data files, and none qualifies

| Dataset | Files | Size | Verdict |
|---|---:|---:|---|
| `testdatabox/finance-fraud-and-loans` | 11 | **1.2 MB** | **Synthetic** ("TestDataBox") and trivially small |
| `akrambelha/synthetic-banking-dataset` | 6 | 172 MB | **Explicitly synthetic** — disqualified by project rule |
| `beatafaron/loan-credit-risk-population-stability` | 4 | 602 MB | Lending Club **split by year** — flat tables, not relational |
| LTFS variants (×3 mirrors) | 3 | 12 MB | train/test/submission — one flat table |
| `deloitte-hackathon-loan-defaulter` | 3 | 9 MB | train/test/submission — one flat table |

### The structural finding: this space is bimodal

Real, genuinely relational lending data exists in only two forms:

- **Small academic teaching extracts** — PKDD'99/Berka: 8 tables, but 682 loans and 76 bad outcomes
- **Large competition dumps** — Home Credit: 7 tables, but 58M rows

**There is nothing in between**, and there is a reason. Relational lending data comes out of
production core-banking systems. An institution either releases a small anonymised teaching extract
or a large one-off competition dataset. Nobody publishes a mid-sized relational loan book, because
mid-sized is exactly the range where re-identification risk is highest and commercial value is
still real.

### Bondora — the strongest *smaller* candidate, examined properly

Bondora (Estonian P2P) publishes its complete loan book. Verified against three Kaggle mirrors:

| Mirror | Files | Size |
|---|---|---:|
| `sid321axn/bondora-peer-to-peer-lending-loan-data` | `LoanData_Bondora.csv` only | 150 MB |
| `marcobeyer/bondora-p2p-loans` | `LoanData.csv` only | 230 MB |
| `dumbstatistician/loan-data-bondora` | `LoanData.csv` only | 332 MB |

**One flat table** (~200k–350k loans × 112 columns). No repayments table.

What it uniquely offers that Home Credit cannot: **real calendar dates** (2009–2020) → true vintage
analysis; **country-level geography**; **days-past-due in actual days** plus late-category buckets;
and — uniquely among every candidate — **recovery amounts, Loss Given Default and Exposure at
Default**, i.e. genuine collections *outcomes*. Home Credit has none of these.

What it costs: **the entire relational dimension.** No joins, no grain hierarchy, no fan-out
reasoning — the project's signature technical capability and a stated HIGH priority.

Availability risk also noted: Bondora's public-reports page currently redirects to `goandgrow.eu`
and states it is "being revamped", so the canonical source is in flux. The Kaggle mirrors are
static snapshots.

### Conclusion of round 3

**No smaller real dataset preserves the relational/grain/join capability.** Per Rahul's own
instruction — *"if no suitable replacement exists, return to Home Credit and design the minimum
necessary reduction based on evidence"* — Home Credit stands, with a minimal evidence-based
reduction rather than module removal.

---

## 6. Recommendation

**Keep Home Credit. Do not switch datasets. Reduce the working footprint instead.**

Reasoning:
1. **No Indian alternative exists** — confirmed three independent ways.
2. **No smaller real dataset preserves the HIGH-priority modules.** Berka fails on outcome count;
   Freddie Mac fails on relational depth; LTFS fails on structure.
3. **Switching costs ~2 of the remaining 8–10 days** and discards findings F1, F2, F8, Q5 and Q17 —
   including the grain discovery that is currently the strongest interview material in the project.
4. The problem is **working latency, not the dataset's validity.** That is fixable without changing
   the source.

### Proposed changes

**Change 1 — drop the external bureau module entirely** (his Option C: remove a component).
Removes `bureau` + `bureau_balance` = **29,016,353 rows, exactly half the database.**
Lost: external credit-history signals for early warning, external roll rate.
Kept: everything HIGH priority. Internal panels already carry delinquency history.

**Change 2 — build a compact analytical mart, then work on the mart.**
Heavy panel computation runs ~3 times total, not once per query. Day-to-day working tables:

| Mart table | Rows | Inspectable? |
|---|---:|---|
| `mart_customer` (features + `TARGET`) | 356,255 | yes |
| `mart_account` (book snapshot + history summary) | 1,040,632 | yes |
| `mart_account_month` (panel, POS+CARD) | 13,841,670 | computed once |
| `mart_collections_queue` | 7,211 | **fully inspectable** |
| `mart_roll_rate` (pre-computed matrix) | ~36 | yes |

After the one-time build every analytical query runs on ≤1M rows.

**Change 3 — reprioritise two modules honestly.**
- **M12 collections** stays, scoped truthfully: a ranked queue over the **7,211 delinquent accounts
  in the live book** (2,048 at 30+ DPD). That is a realistic size for a real collections team — but
  we state plainly that it comes from a 58M-row source.
- **M7 roll rate** moves from MEDIUM to *computed once, reported, not iterated* — because each
  iteration costs 4.5 minutes and it is not a HIGH-priority module.

### What we would still be unable to do
Geography (no state/city). Calendar-dated trends or calendar vintages. Collections effectiveness or
recovery rates. Loss Given Default. No claim that the data represents India.

---

## 7. The honest alternative

If **calendar-time analysis** matters more to you than **relational depth**, Freddie Mac's sample
dataset is the better dataset — real vintages by origination quarter, a real DPD ladder, real US
state geography, and a manageable ~2.5M rows per vintage year.

The cost is real: two tables instead of seven, thin borrower attributes, no installment-level
repayment behaviour, no `TARGET`-style validation design, and roughly two days to redo Phases 2–5.

I do not recommend it — but it is a legitimate choice, and it is yours to make.
