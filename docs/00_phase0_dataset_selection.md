# Phase 0 — Dataset Selection & Feasibility Assessment

**Project:** Loan Portfolio, Delinquency & Collections Intelligence System
**Analyst:** Rahul Meena
**Date:** 2026-09-04
**Status:** ✅ **APPROVED 2026-09-04** — Home Credit Default Risk confirmed as the project dataset
after the Phase 0-A India investigation ([00a_india_dataset_investigation.md](00a_india_dataset_investigation.md)).
Timeline confirmed at 10–15 days. Proceeding to Phase 1.

---

## 0.1 Why this project is strategically stronger than the alternatives

My existing resume already carries:

1. SQL-Based Multi-Bank Performance Analytics
2. Restaurant Analytics (Power BI)
3. An internship covering SQL/Python data foundations, modeling, optimisation, analytics

The gap that leaves is **longitudinal, behavioural, decision-producing analytics**. Items 1–3 are
largely cross-sectional — they describe a state. Nothing in the profile yet demonstrates the ability to
analyse *the same entity observed repeatedly over time* and turn that into an operational decision.

| Dimension | Previous idea (Product Growth & Experimentation) | This project |
|---|---|---|
| Domain fit for ICICI Bank | Weak — tech/product-org framing | Strong — lending is a bank's core P&L; collections is a live cost centre |
| Analytical axis added to profile | A/B testing, funnel metrics | Panel/time-series behaviour, state transitions, cohort curves |
| Differentiation in a placement pool | Low — very common | High — roll-rate, vintage, DPD analysis is rare in student portfolios |
| Output type | A report | A **decision artifact** (a prioritised collections queue) |
| Overlap with existing resume | Moderate (dashboarding again) | Low — new domain, new technique class |
| Vocabulary gained | Product analytics terms | DPD, delinquency, roll rate, vintage, exposure, collections |

**Honest cost of this choice:** it is conceptually heavier. I have to genuinely learn credit concepts
(DPD, roll rate, vintage, exposure) rather than just write SQL. That learning is the point, but it is
real work and it is why the phases below are deliberately slow at the start.

**What this project must NOT become:** a Kaggle default-prediction notebook. The dataset is a *source*,
not the project's identity. The deliverable is a portfolio-monitoring and collections-prioritisation
system, evidenced by SQL.

---

## 0.2 STEP 1 — The India-first dataset search

Per the India-first strategy, real Indian lending data was searched for **before** any global option
was considered. Findings, grouped by tier:

### Tier A — RBI / Government of India (real, authoritative, but AGGREGATED)

| Source | What it contains | Grain | Verdict |
|---|---|---|---|
| RBI **BSR-1** (Basic Statistical Return, Annual & Quarterly) — Credit by Scheduled Commercial Banks | Outstanding credit by district, population group, occupation, organisation type, borrower category, secured/unsecured, interest rate band | Bank × district × category aggregate | **Insufficient.** BSR-1A is *collected* from banks at borrowal-account level, but **published only in aggregated form**. No borrower ID, no repayment timeline. |
| RBI **Sectoral Deployment of Bank Credit** | Monthly credit outstanding by sector/sub-sector | Sector × month | Insufficient — macro only |
| RBI **Financial Stability Report / Trend & Progress** | GNPA/NNPA ratios, slippage, provisioning | Bank-group × period | Insufficient as data; **useful as context** |
| **data.gov.in** — e.g. "Year-wise Recovery in Written-off Loans under RBI 2017-18 to 2021-22"; PMMY/Mudra, KCC datasets | Recovery amounts, disbursement counts | Year × scheme × state | Insufficient — no account grain |
| RBI **Public Credit Registry (PCR)** | Designed to hold borrower-level credit + delinquency data | Borrower-level *by design* | **Not publicly released** as an open dataset. Regulatory infrastructure, not open data. |

**Conclusion for Tier A:** RBI/GoI publish *statistics about* Indian lending, not *records of* Indian
loans. They are excellent for framing the business problem in the README (India's retail credit growth
and GNPA context) but cannot serve as the analytical base.

### Tier B — Indian, loan-level, real, but structurally flat

| Dataset | Reality check | Structure | Blocking gaps |
|---|---|---|---|
| **LTFS / L&T Financial Services vehicle loan** (Analytics Vidhya "DataScience FinHack", ~233k rows) | **Genuinely Indian** — `State_ID`, `branch_id`, Aadhaar/PAN/Voter-ID/Driving-licence flags, CIBIL-style `PERFORM_CNS.SCORE`, `DisbursalDate` | **Single flat table.** train.csv + data_dictionary.csv. Bureau history is present only as pre-aggregated counts (`DELINQUENT.ACCTS.IN.LAST.SIX.MONTHS`, `AVERAGE.ACCT.AGE`, `PRI.OVERDUE.ACCTS`, …) | No installment table. No monthly performance panel. Target = default on the **first EMI only** → no delinquency progression, no roll rate, no vintage curve, no active-book collections queue, no multi-table grain/fan-out work. Licence for public republication is ambiguous (hackathon terms). |
| Kaggle "Indian Banks Loan Dataset", "Loan_Prediction_India", "India Wilful Loan Defaulters" | Mixed. The classic Indian loan-prediction file is ~614 rows. The wilful-defaulters file is a **list of names/amounts**, not repayment behaviour. Several are undocumented re-uploads of unclear provenance and several are likely synthetic. | Flat, tiny | Fail the "real + documented + validatable" bar |
| Kaggle "NBFI Vehicle Loan repayment", "Microfinance Loan" datasets | Provenance not established as Indian; "NBFI" is Bangladeshi usage. Documentation thin. | Flat | Cannot verify the observations are India-specific — the strategy explicitly forbids assuming Indian-ness from a title |

### STEP 2/3/4 verdict on India

The India-first strategy says: prefer Indian data **only if sufficient**, and do not force weak Indian
data. Applying that test:

**What Indian datasets COULD support:** application-time risk profiling; first-EMI default rates by
state / employment type / bureau-score band / loan-to-value; portfolio composition at origination.

**What they CANNOT support — and these are the spine of this project:**

- Days-past-due measurement over time
- Delinquency state transitions (roll rates)
- Vintage / months-on-book deterioration curves
- Installment-level repayment behaviour (due date vs actual payment date, shortfall)
- Exposure on an active book → a collections priority queue
- Multi-table relational modelling, grain reasoning and join fan-out control

Six of the seven analytical modules I set out to build are unbuildable on public Indian data.
**Therefore: proceed to Step 5 — select the strongest real non-Indian dataset, as an explicit,
documented decision.**

This will be stated openly in the README. The project will **not** be dressed up as Indian data.

---

## 0.3 Candidate comparison — scoring matrix

Scores 0–5 per criterion, multiplied by weight. Weights reflect what *this specific project* needs.

| # | Criterion | Wt | Home Credit | Freddie Mac SFLLD | Lending Club | LTFS (India) | PKDD'99 Czech | Prosper |
|---|---|---|---|---|---|---|---|---|
| 1 | Real (not synthetic) | gate | PASS | PASS | PASS | PASS | PASS | PASS |
| 2 | Relational / multi-table depth | 5 | **5** | 2 | 1 | 1 | 5 | 1 |
| 3 | Monthly performance panel with DPD | 5 | **5** | 5 | 1 | 0 | 2 | 1 |
| 4 | Installment-level repayment behaviour | 4 | **5** | 2 | 2 | 0 | 3 | 2 |
| 5 | Exposure / outstanding balance | 4 | 4 | **5** | 4 | 2 | 3 | 4 |
| 6 | Calendar time & true vintage cohorts | 3 | **1** | 5 | 5 | 2 | 5 | 5 |
| 7 | Borrower & product attributes | 3 | **5** | 2 | 4 | 4 | 4 | 4 |
| 8 | Genuine data-quality challenge | 3 | **5** | 3 | 4 | 4 | 4 | 4 |
| 9 | Collections decision framing | 4 | **4** | 2 | 3 | 2 | 2 | 3 |
| 10 | MySQL feasibility on 8 GB laptop | 3 | 3 | 4 | **5** | 5 | 5 | 5 |
| 11 | Documentation & credibility | 3 | **5** | 5 | 4 | 3 | 4 | 3 |
| 12 | India relevance | 2 | 2 | 0 | 0 | **5** | 0 | 0 |
| | **Weighted total (max 195)** | | **163** | 128 | 112 | 85 | 133 | 109 |
| | **%** | | **84%** | 66% | 57% | 44% | 68% | 56% |

### Scale gate

| Dataset | Loan/account count | Passes "portfolio" scale? |
|---|---|---|
| Home Credit | 307,511 applications + 1.67M prior contracts + 1.72M bureau credits | Yes |
| Freddie Mac (sample) | 50,000 loans/year × 25 years | Yes |
| Lending Club | ~2.26M accepted loans | Yes |
| LTFS | ~233k loans | Yes |
| **PKDD'99 Czech (Berka)** | **682 loans** | **NO — disqualified.** Beautiful relational teaching set, real 1993–98 Czech bank data, 8 tables including district demographics. But you cannot credibly call 682 loans a "portfolio". |
| Prosper | ~114k loans | Yes |

### Head-to-head: the only two serious contenders

| | **Home Credit Default Risk** | **Freddie Mac Single-Family Loan-Level** |
|---|---|---|
| Tables | 7 (+1 column-description file) | 2 (origination, monthly performance) |
| Levels of grain | 4 (person → contract → month → installment) | 2 (loan → loan-month) |
| DPD | `SK_DPD` / `SK_DPD_DEF` monthly, on internal accounts; `STATUS` 0–5 monthly on external bureau credits | `Current Loan Delinquency Status` monthly, MBA method |
| Installment-level payments | **Yes** — due date, due amount, payment date, payment amount, per installment | No — monthly UPB + due-date-of-last-paid-installment only |
| Calendar dates | **No** — everything is relative to each client's application date | **Yes** — true monthly reporting periods, 1999–2025 |
| Borrower/product richness | 122 application columns + product/channel/purpose on prior contracts | ~32 columns: FICO, LTV, DTI, purpose, occupancy, state, channel |
| Product type | Consumer finance: cash loans, revolving/credit card, POS/consumer durable | Fixed-rate residential mortgage only |
| Access | Kaggle account, direct download | Registration + login to Freddie Mac "Clarity Data Intelligence" |
| Best at | Relational modelling, grain/fan-out, repayment behaviour, early warning, data quality | Calendar vintages, textbook roll rates, exposure |
| Weak at | Calendar cohorts, single as-of date | Relational depth, borrower richness, collections framing |

**Recommendation: Home Credit Default Risk.**

Reasoning: five of the six criteria I weighted at 4–5 (relational depth, DPD panel, installment
behaviour, borrower richness, collections framing, data-quality challenge) are where Home Credit is
strongest, and the one place it loses badly — calendar time — has a legitimate and *defensible*
workaround, because real vintage analysis is conducted in **months-on-book**, not calendar months,
anyway. Freddie Mac would give me a cleaner roll-rate chapter and a much thinner everything-else, and
its 2-table shape removes precisely the grain-and-fan-out reasoning I most want to be able to defend
in an interview.

**India-relevance positioning (honest version):** Home Credit Group is a multi-country consumer
lender that did operate in India (Home Credit India Finance Pvt Ltd) — but **the dataset does not
disclose its country of origin, so no Indian claim will be made anywhere in this project.** The
relevance to ICICI is that the *product class* is retail consumer credit and the *analytical
framework* — portfolio monitoring, DPD bucketing, roll rates, vintage curves, collections
prioritisation — is the standard toolkit of any retail lending analytics function, ICICI included.

---

## 0.4 Home Credit — tables, keys and grain

| # | Table | Rows | Cols | Primary key | Foreign key(s) | **One row represents…** |
|---|---|---|---|---|---|---|
| 1 | `application_train` | 307,511 | 122 | `SK_ID_CURR` | — | **one current loan application by one client** (1:1 with client in this file) |
| 2 | `bureau` | 1,716,428 | 17 | `SK_ID_BUREAU` | `SK_ID_CURR` | **one credit the client holds/held at another institution**, as reported by the credit bureau |
| 3 | `bureau_balance` | 27,299,925 | 3 | (`SK_ID_BUREAU`,`MONTHS_BALANCE`) | `SK_ID_BUREAU` | **one month of status history for one external credit** |
| 4 | `previous_application` | 1,670,214 | 37 | `SK_ID_PREV` | `SK_ID_CURR` | **one previous application to Home Credit** (approved, refused, cancelled or unused) |
| 5 | `POS_CASH_balance` | 10,001,358 | 8 | (`SK_ID_PREV`,`MONTHS_BALANCE`) | `SK_ID_PREV`,`SK_ID_CURR` | **one month of a POS/cash loan account's status** |
| 6 | `credit_card_balance` | 3,840,312 | 23 | (`SK_ID_PREV`,`MONTHS_BALANCE`) | `SK_ID_PREV`,`SK_ID_CURR` | **one month of a credit-card account's balance and status** |
| 7 | `installments_payments` | 13,605,401 | 8 | ⚠️ **none — see Phase 2** | `SK_ID_PREV`,`SK_ID_CURR` | ⚠️ **CORRECTED in Phase 2: one row = one *payment event*, not one installment.** An installment paid in parts produces multiple rows. See [02_dataset_inspection.md](02_dataset_inspection.md). |

**Total ≈ 58.4 million rows.**

### Entity identity

| Identifier | Represents | Lives in |
|---|---|---|
| `SK_ID_CURR` | the **person / current applicant** | all 7 tables except `bureau_balance` |
| `SK_ID_PREV` | one **previous Home Credit contract** | `previous_application`, `POS_CASH_balance`, `credit_card_balance`, `installments_payments` |
| `SK_ID_BUREAU` | one **external credit** reported by the bureau | `bureau`, `bureau_balance` |
| (`SK_ID_PREV`, `NUM_INSTALMENT_NUMBER`) | one **payment event** | `installments_payments` |

### The grain hierarchy (this is the fan-out map)

```
PERSON  (SK_ID_CURR)                       307,511
   │
   ├── internal prior contracts (SK_ID_PREV)         1,670,214   ~5.4 per person
   │        ├── monthly account status               10,001,358  (POS/cash)
   │        ├── monthly card balance                  3,840,312  (credit card)
   │        └── installment events                   13,605,401  ~8.1 per contract
   │
   └── external bureau credits (SK_ID_BUREAU)         1,716,428  ~5.6 per person
            └── monthly bureau status                27,299,925  ~15.9 per credit
```

Joining person → installments without pre-aggregating multiplies each person's row by ~44.
**This is exactly the fan-out lesson the project is built to teach.**

### The critical structural fact about time

**Every date in this dataset is relative, not absolute.** There is not one calendar date anywhere:

- `DAYS_BIRTH`, `DAYS_EMPLOYED`, `DAYS_REGISTRATION` — negative days before the current application
- `DAYS_CREDIT`, `DAYS_CREDIT_ENDDATE` (bureau) — days relative to current application
- `DAYS_DECISION`, `DAYS_FIRST_DUE`, `DAYS_LAST_DUE` (previous_application) — same
- `DAYS_INSTALMENT`, `DAYS_ENTRY_PAYMENT` (installments) — same
- `MONTHS_BALANCE` — month index relative to the current application, where `-1` = the month before it

**Consequence #1:** Calendar cohorts ("Q1-2023 originations vs Q2-2023") are impossible.
**Consequence #2:** `MONTHS_BALANCE = -1` means *one month before that client's own application*.
Different clients applied on different real dates. So a cross-sectional "as-of" snapshot is a
**relative-time snapshot**, not a single calendar date.

Both consequences will be stated explicitly in the methodology and both are, in my view, *interview
assets* rather than embarrassments — they force me to reason about observation-window alignment.

---

## 0.5 Data-sufficiency matrix

| # | Analysis / business question | Required data | Available? | Table(s) | Key column(s) | Grain of answer | Assumption / limitation |
|---|---|---|---|---|---|---|---|
| 1 | Portfolio size & composition of the application book | Application volume, amount, product | **Yes** | `application_train` | `SK_ID_CURR`, `AMT_CREDIT`, `NAME_CONTRACT_TYPE` | application | Book = one snapshot of applications, not an ongoing ledger |
| 2 | Borrower profile of the book | Income, employment, education, family, age | **Yes** | `application_train` | `AMT_INCOME_TOTAL`, `NAME_INCOME_TYPE`, `OCCUPATION_TYPE`, `DAYS_BIRTH` | application | `DAYS_EMPLOYED` carries a `365243` sentinel; `XNA`/`Unknown` categories present |
| 3 | Delinquency **by named geography** (state/city) | State or city name | **NO** | — | — | — | **Cannot be answered.** Only `REGION_RATING_CLIENT` (1–3), `REGION_POPULATION_RELATIVE` and region-mismatch flags exist. Geography will be an anonymised region-rating dimension only. |
| 4 | Active account book & exposure — credit cards | Outstanding balance at latest month | **Yes** | `credit_card_balance` | `AMT_BALANCE`, `AMT_TOTAL_RECEIVABLE`, `NAME_CONTRACT_STATUS` | contract-month | Latest month is per-client relative, not a common calendar date |
| 5 | Active account book & exposure — POS/cash loans | Outstanding balance | **Partial / derived** | `POS_CASH_balance` + `previous_application` | `CNT_INSTALMENT_FUTURE` × `AMT_ANNUITY` | contract-month | **Assumption:** remaining exposure ≈ future installments × annuity. Ignores interest split and prepayment. Must be labelled a proxy. |
| 6 | Credit-card utilisation | Balance ÷ limit | **Yes** | `credit_card_balance` | `AMT_BALANCE`, `AMT_CREDIT_LIMIT_ACTUAL` | contract-month | Limit is "actual" at that month; zero/NULL limits must be excluded |
| 7 | Days past due (DPD) on internal accounts | DPD per account per month | **Yes** | `POS_CASH_balance`, `credit_card_balance` | `SK_DPD`, `SK_DPD_DEF` | contract-month | `SK_DPD_DEF` is DPD ignoring low-value tolerance — I must pick one and justify it |
| 8 | DPD bucketing (Current / 1–30 / 31–60 / 61–90 / 90+) | Numeric DPD | **Yes** | as above | `SK_DPD` | contract-month | Buckets are my definition, not the lender's policy — must be labelled |
| 9 | External credit delinquency status | Monthly status per external credit | **Yes** | `bureau_balance` | `STATUS` (C, X, 0–5) | bureau-credit-month | `X` = unknown; must be handled explicitly, not silently dropped. 27.3M rows. |
| 10 | On-time payment rate | Due date vs actual payment date | **Yes** | `installments_payments` | `DAYS_ENTRY_PAYMENT` − `DAYS_INSTALMENT` | installment | NULL payment dates exist (unpaid/not-yet-recorded). Sign convention must be verified in Phase 5. |
| 11 | Payment shortfall / underpayment | Due amount vs paid amount | **Yes** | `installments_payments` | `AMT_INSTALMENT` − `AMT_PAYMENT` | installment | Multiple `NUM_INSTALMENT_VERSION` rows exist per installment (rescheduling) — **duplicate risk** |
| 12 | Repayment deterioration (recent vs historical) | Ordered payment history | **Yes** | `installments_payments` | `DAYS_INSTALMENT` ordering + window functions | contract → person | Requires `LAG`/moving windows; "recent" must be defined (e.g. last 6 installments) |
| 13 | **Roll-rate** (bucket-to-bucket transitions) | Same account observed in consecutive months | **Yes** | `POS_CASH_balance` / `credit_card_balance` / `bureau_balance` | `LAG(bucket) OVER (PARTITION BY account ORDER BY MONTHS_BALANCE)` | contract-month pair | Transitions are in **relative** months. Gaps in the monthly series must be detected, not assumed. |
| 14 | **Vintage / months-on-book curves** | Cohort + age + performance | **Yes (MOB-based)** | `POS_CASH_balance` + `previous_application` | `MONTHS_BALANCE` − first observed month; `DAYS_DECISION` for cohort | contract-month | **Cohorts are origination-recency bands** (e.g. "originated 0–12 months before application"), **not calendar quarters.** This is the single biggest limitation. |
| 15 | Prior-delinquency history of an applicant | Historical DPD/status aggregated to person | **Yes** | `bureau`+`bureau_balance`, `POS_CASH_balance` | `CREDIT_DAY_OVERDUE`, `AMT_CREDIT_SUM_OVERDUE`, `STATUS`, `SK_DPD` | person | Must aggregate to person grain *before* joining to avoid fan-out |
| 16 | Credit-hunger / repeated applications | Bureau enquiry counts | **Yes** | `application_train` | `AMT_REQ_CREDIT_BUREAU_DAY/WEEK/MON/QRT/YEAR` | application | Nulls present; enquiry ≠ application |
| 17 | Rejection behaviour | Prior application outcomes | **Yes** | `previous_application` | `NAME_CONTRACT_STATUS`, `CODE_REJECT_REASON` | prior application | Reject reasons include `XAP`/`XNA` placeholders |
| 18 | **Early-warning framework** | Signals + an outcome to test against | **Yes** | all + `application_train.TARGET` | `TARGET` | person | `TARGET` = client had payment difficulty (late beyond a threshold on an early installment) on the **current** loan. Signals are **associated with**, not causes of, default. |
| 19 | **Validation of early-warning signals** | Observed outcome rate by signal count | **Yes** | `application_train.TARGET` | `TARGET` | person | This is the project's strongest evidence base — the signal framework is testable, not asserted |
| 20 | **Collections prioritisation queue** | Delinquent + exposure + deterioration at latest observation | **Yes** | `POS_CASH_balance`/`credit_card_balance` + derived exposure | `SK_DPD`, `AMT_BALANCE`, priority score | account | Prioritisation only. **No collections-outcome data exists**, so no claim about recovery effectiveness can be made. |
| 21 | Did collections action work? / recovery rates | Contact, promise-to-pay, recovery, write-off records | **NO** | — | — | — | **Cannot be answered.** No collections operations data. Must be listed as a limitation and a "with production data" improvement. |
| 22 | Interest rate / yield analysis | Rate per contract | **Partial** | `previous_application` | `RATE_INTEREST_PRIMARY`, `NAME_YIELD_GROUP` | prior contract | Rate columns are ~99% null; only the coarse `NAME_YIELD_GROUP` band is usable |
| 23 | Loss given default / provisioning | Recovery amounts, collateral realisation | **NO** | — | — | — | **Cannot be answered.** |
| 24 | Calendar-time portfolio trend ("NPA rising since March") | Absolute dates | **NO** | — | — | — | **Cannot be answered.** Only relative-time trends. |

**Rule applied throughout: no field will be invented.** Rows 3, 21, 23 and 24 are permanent
"cannot answer" entries and will appear in the Limitation Register verbatim.

---

## 0.6 What this project CAN and CANNOT claim

### CAN
- Describe the composition, size and borrower profile of a consumer-lending book
- Measure days-past-due and bucket accounts into delinquency states
- Measure genuine installment-level repayment behaviour (lateness, shortfall, consistency)
- Compute month-over-month delinquency **roll rates** on real account panels
- Build **months-on-book vintage curves** by origination-recency cohort
- Build a transparent, rule-based **early-warning framework** and **test it against an observed
  default outcome** — producing real, quoted lift numbers
- Produce a ranked **collections priority list** with a stated, auditable scoring rule
- Demonstrate serious relational modelling, grain control and fan-out avoidance in MySQL
- Demonstrate real data-quality forensics (sentinels, placeholders, orphans, duplicates)

### CANNOT
- Analyse anything by named geography (no state/city in the data)
- Produce calendar-dated trends or calendar-quarter vintage cohorts
- Measure collections effectiveness, recovery rates, or loss given default
- Claim causality between any signal and default
- Claim the data represents India, or any named country
- Claim the DPD buckets or priority tiers match any real lender's policy

---

## 0.7 MySQL feasibility on this machine

**Hardware:** AMD Ryzen 5 5500U (6C/12T), **7.3 GB RAM**, **45.9 GB free on C:**
**Software:** MySQL Server 8.0 (service `MySQL80`, running), MySQL Workbench 8.0. `mysql` CLI is not on PATH — will need the full path or a PATH entry.

### Size estimate

| Item | Estimate |
|---|---|
| Raw CSVs (uncompressed) | ~2.7 GB |
| InnoDB tables + primary keys | ~6–8 GB |
| Secondary indexes needed for analysis | ~2–4 GB |
| Temp/sort space during index builds and big GROUP BYs | ~3–5 GB peak |
| **Total peak disk** | **~12–17 GB** |

45.9 GB free is enough, but not comfortable — a runaway temp file or an accidental unindexed join on
27M rows could get uncomfortable. RAM is the tighter constraint: on 7.3 GB total,
`innodb_buffer_pool_size` can reasonably go to ~2 GB, which means the large panel tables **will not**
fit in memory and every scan is disk-bound.

### Recommended loading strategy — **staged**

**Stage 1 (load first, ~29.1M rows):** `application_train`, `bureau`, `previous_application`,
`POS_CASH_balance`, `credit_card_balance`, `installments_payments`.
This alone supports modules 1–8, 10–20 in the sufficiency matrix — i.e. *the entire project except
the external-bureau roll-rate module*.

**Stage 2 (conditional, 27.3M rows):** `bureau_balance`. Load only after Stage 1 works, and only if
we decide the external-bureau delinquency panel adds enough beyond the internal panels. Its analytical
value overlaps substantially with `POS_CASH_balance`.

**Fallback if Stage 1 is painful — a documented customer sample:** draw a reproducible random sample
of `SK_ID_CURR` (e.g. 30%) and filter *every* child table by that same ID set. This preserves
referential integrity and every table's grain, and the sampling itself becomes a validation exercise
(compare `TARGET` rate and key distributions between sample and full file). Documented as a decision,
not hidden.

### Loading technique
- `LOAD DATA LOCAL INFILE` (needs `local_infile=1` on both server and client), **not** the Workbench
  import wizard — the wizard is row-by-row and would take hours on 13M rows
- Create tables **without secondary indexes**, load, then `ALTER TABLE … ADD INDEX` — far faster
- `SET unique_checks=0; SET foreign_key_checks=0; SET autocommit=0;` during load, restored after
- Handle Windows `secure_file_priv` (either use `LOCAL`, or place files in the permitted directory)
- Raise `innodb_buffer_pool_size` to ~2 GB in `my.ini`

### Workbench discipline
Never `SELECT *` on a panel table — Workbench's result grid holds results in memory and 10M rows will
freeze it. Every exploratory query gets a `LIMIT` or an aggregate.

**Feasibility verdict: YES, with the staged plan.** This is the single largest execution risk in the
project and it is front-loaded into Phase 4 deliberately.

---

## 0.8 Initial risk register

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | Loading 13M+ row tables is slow or fails on 7.3 GB RAM | Medium | High | Staged load; `LOAD DATA LOCAL INFILE`; index after load; documented sample fallback |
| R2 | Disk pressure (45.9 GB free) during index builds | Medium | High | Stage 2 optional; monitor free space; drop unused indexes |
| R3 | Relative-time structure weakens the "portfolio monitoring" narrative | High | Medium | Reframe explicitly as relative-time / months-on-book analysis; state it in README and interview answer |
| R4 | Fan-out double counting silently corrupts a headline number | Medium | High | Aggregate-to-grain-then-join discipline; row-count reconciliation on every multi-table query; a dedicated fan-out chapter |
| R5 | Project drifts into a default-prediction ML notebook | Medium | High | No model unless explicitly agreed; early-warning stays rule-based and transparent |
| R6 | Scope too large for the available days | High | Medium | Phase plan below is prioritised; modules 8/9 (bureau panel) are droppable without breaking the story |
| R7 | Over-claiming business impact | Medium | High | Language rules enforced: "associated with", "observed", "suggests"; no fabricated ₹/% impact |

---

## 0.9 Recommended scope

**Title:** Loan Portfolio, Delinquency & Collections Intelligence System
**Dataset:** Home Credit Default Risk (Kaggle) — 7 tables, ~58.4M rows, real anonymised consumer-lending data
**Stack:** MySQL 8.0 (core), Power BI (decision layer), Python (validation only)

**Business problem (draft — to be finalised in Phase 1):**
> A consumer lender holds an active book of POS/cash and revolving credit accounts, alongside a rich
> history of each borrower's internal and external credit behaviour. The portfolio and collections
> functions lack a single, evidence-based view of *where repayment stress is concentrated*, *how
> quickly accounts deteriorate once they slip*, and *which delinquent accounts deserve the limited
> collections capacity first*. This project builds that view from the transaction-level data up.

**Modules:** Data quality → Portfolio baseline → Repayment behaviour → Delinquency & DPD →
Vintage (MOB) → Roll rate → Early warning (validated against observed default) → Collections
prioritisation → Power BI decision layer.

---

## 0.9b Data acquisition & verification record (2026-09-04)

Data acquired and placed in `data/raw/`. **Every figure quoted earlier in this document from published
documentation has now been independently measured and confirmed.**

| File | Bytes (official manifest) | Bytes (on disk) | Data rows | Published rows | Cols |
|---|---:|---:|---:|---:|---:|
| `installments_payments.csv` | 723,118,349 | 723,118,349 ✅ | 13,605,401 | 13,605,401 ✅ | 8 |
| `credit_card_balance.csv` | 424,582,605 | 424,582,605 ✅ | 3,840,312 | 3,840,312 ✅ | 23 |
| `previous_application.csv` | 404,973,293 | 404,973,293 ✅ | 1,670,214 | 1,670,214 ✅ | 37 |
| `POS_CASH_balance.csv` | 392,703,158 | 392,703,158 ✅ | 10,001,358 | 10,001,358 ✅ | 8 |
| `bureau_balance.csv` | 375,592,889 | 375,592,889 ✅ | 27,299,925 | 27,299,925 ✅ | 3 |
| `bureau.csv` | 170,016,717 | 170,016,717 ✅ | 1,716,428 | 1,716,428 ✅ | 17 |
| `application_train.csv` | 166,133,370 | 166,133,370 ✅ | 307,511 | 307,511 ✅ | 122 |
| `application_test.csv` | 26,567,651 | 26,567,651 ✅ | 48,744 | 48,744 ✅ | 121 |
| `sample_submission.csv` | 536,202 | 536,202 ✅ | 48,744 | — | 2 |
| `HomeCredit_columns_description.csv` | 37,383 | 37,383 ✅ | 219 | — | 5 |
| **Total** | **2,684,261,617** | **2,684,261,617 ✅** | **58,441,594** | | |

**10/10 byte-exact. 8/8 row counts exact. Headers confirmed** against the expected schema for every
table (e.g. `installments_payments` = `SK_ID_PREV, SK_ID_CURR, NUM_INSTALMENT_VERSION,
NUM_INSTALMENT_NUMBER, DAYS_INSTALMENT, DAYS_ENTRY_PAYMENT, AMT_INSTALMENT, AMT_PAYMENT`).

`HomeCredit_columns_description.csv` contains **219 column definitions** — the official data dictionary
that Phase 2 will be built on.

**Provenance note (honest record):** the official Kaggle competition API repeatedly returned
`403 RulesAcceptanceRequired` for this account (`user_has_entered: False` on competition id 9120), so
the CLI route could not be used. The archive was obtained through the browser instead. Its contents
were then verified file-by-file against the **official Kaggle competition manifest**, retrieved from
Kaggle's own API with the authenticated account. All ten files match the official release exactly on
byte size, and all eight data tables match on row count and column count. The data is therefore
confirmed to be the official Home Credit Default Risk release.

Verified manifest saved as `data/raw/_manifest_verified.json`.

---

## 0.10 Phase 0 wrap-up

**What we did:** Searched Indian public lending data across RBI, data.gov.in and public repositories;
tested each candidate for sufficiency; scored six real global datasets against weighted criteria;
mapped the winner's tables, keys and grain; built a 24-row data-sufficiency matrix; measured local
hardware and estimated MySQL load.

**Why:** Because the dataset determines what the project can honestly claim. Choosing it after the
analysis plan, rather than before, is what prevents a fabricated project.

**What we learned:**
1. India publishes *statistics about* lending, not *records of* loans — the granularity gap is a
   regulatory/privacy fact, not a search failure.
2. Sufficiency beats provenance. A genuinely Indian flat table cannot support roll rates.
3. Home Credit's four levels of grain are its greatest strength and its greatest hazard.
4. Relative-time data forbids calendar cohorts but permits months-on-book vintages — which is how
   vintage analysis is actually done.

**Problems / limitations found:** No named geography. No calendar dates. No collections outcomes.
POS/cash exposure must be derived. `bureau_balance` is 27.3M rows on a 7.3 GB machine.

**What comes next:** Phase 1 — business problem, scope and stakeholders, written against the
capabilities this matrix proves we have.
