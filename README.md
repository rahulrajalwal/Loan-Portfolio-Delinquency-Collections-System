# Loan Portfolio, Delinquency & Collections Intelligence System

**A SQL-first lending analytics project on 58.4 million rows of real consumer-credit data.**

MySQL 8.0 · Python · ~2,600 lines of SQL across 17 files

---

## The problem

A consumer lender has **327,101 active** loans and credit cards. **7,211** of those customers are
behind on payments. The collections team can make perhaps 300 calls a day.

**Which customers do they call first?**

The instinctive answer — call the ones furthest behind — is what most collections queues do. This
project tested whether that is right.

It is not. And the size of the error is measurable.

| Capacity worked | Ranked by **days past due** | Ranked by **exposure × observed cure rate** |
|---:|---:|---:|
| 5% | 0.00% | 57.59% |
| **10%** | **0.00%** | **79.82%** |
| 20% | 0.00% | 96.29% |

Working the top 10% of the queue sorted by severity reaches **none** of the recoverable money.

### Why

| Bucket | Accounts | Total exposure | **Mean balance** | Observed cure rate |
|---|---:|---:|---:|---:|
| 1–30 days late | 5,163 | ₹465.7M | ₹91,648 | 55.4% |
| 31–90 days | 372 | ₹101.2M | ₹281,140 | 24.5% |
| 91–360 days | 307 | ₹18.2M | ₹63,226 | 6.0% |
| **360+ days** | **1,369** | **₹0.2M** | **₹179** | **2.0%** |

The most overdue accounts are written-off balances with a still-running counter. There is no money in
them. Sorting by severity spends the team's entire day there.

---

## Why it matters

Collections capacity is finite. Every hour on an account that will never pay is an hour not spent on
one that might — and because nobody sees the counterfactual, a badly ordered queue still looks busy.

This is **hospital triage**. Patients are not treated by who has waited longest; they are treated by
how serious *and* how treatable. "Most days overdue" is the same mistake as "longest waiting".

---

## The dataset

**Home Credit Default Risk** — real, anonymised consumer-lending data published by Home Credit Group.

| Table | Rows | One row = |
|---|---:|---|
| `application` | 356,255 | one loan application |
| `bureau` | 1,716,428 | one credit at another institution |
| `previous_application` | 1,670,214 | one prior contract with this lender |
| `pos_cash_balance` | 10,001,358 | one month of a POS/cash account |
| `credit_card_balance` | 3,840,312 | one month of a card account |
| `installments_payments` | 13,605,401 | **one payment event** — see finding F1 |
| `bureau_balance` | 27,299,925 | one month of an external credit |
| **Total** | **58,441,594** | 356,255 borrowers · 1,040,632 accounts |

> **Provenance.** Real India-specific lending data was searched first, across 14 source families in
> three rounds ([docs/00a](docs/00a_india_dataset_investigation.md)). It exists but is not public:
> India publishes statistics *about* lending, not records *of* loans, for statutory and privacy
> reasons. This dataset's country is not disclosed by its publisher and **no claim is made that it
> represents India or any named market.**

---

## Data model

Four levels of grain, which is both the dataset's strength and its main hazard:

```
PERSON  (SK_ID_CURR)                               356,255
   │
   ├── prior contracts (SK_ID_PREV)              1,670,214   ~4.9 per person
   │        ├── monthly account status          10,001,358   POS / cash
   │        ├── monthly card balance             3,840,312
   │        └── payment events                  13,605,401   ~40 per person
   │
   └── external bureau credits (SK_ID_BUREAU)    1,716,428   ~5.6 per person
            └── monthly bureau status           27,299,925
```

**Measured fan-out:** joining customers to payment events and summing a customer-level amount
inflates the total by **37.5×** — and the multiplier varies per customer, so it cannot be divided out.

No foreign keys are declared: 4.0% of POS and 10.9% of card accounts have genuinely missing parent
contracts (finding F3). Declaring constraints would have rejected real rows.

---

## Method

Twelve evidence-gated phases. The governing rule — *measure before deciding* — overruled the plan
three times:

| Assumed | Measured |
|---|---|
| One row per installment | **One row per payment event.** 653,483 installments settled in parts; one by twelve payments |
| Standard 30-day delinquency buckets | Only **542 accounts** ever peak at 61–90 DPD — too thin for stable rates |
| Lateness measured at full settlement | **First-payment lateness predicts far better** (1.88× vs 1.33×) |

Each was a reasonable prior the data contradicted. They are recorded rather than silently corrected.

### SQL techniques, and the problem each solved

| Technique | Used for |
|---|---|
| `LAG` window functions | Comparing each account-month to the previous one to build the transition matrix |
| `ROW_NUMBER`, `NTILE` | Ranking the same rows two ways to compare orderings; exposure deciles |
| CTEs | Multi-step derivations, each step independently checkable |
| Conditional aggregation | Counting outcomes by category in a single scan |
| `LEFT JOIN` + orphan handling | Preserving the 4% of accounts with genuinely missing parents |
| `EXPLAIN FORMAT=TREE` | Diagnosing why one optimisation could not work |

---

## Analytical modules

| Module | Output |
|---|---|
| Data quality | 15 checks, 17 issues logged with detection, treatment and business impact |
| Portfolio baseline | Book composition, exposure concentration (top decile = **51.6%**) |
| Repayment behaviour | Installment-grain lateness and shortfall, tested against the outcome |
| Delinquency & roll rate | Transition matrix from **12.5M** observed month-to-month pairs |
| Vintage analysis | Cohort curves compared at equal months-on-book |
| Early warning | Five transparent rules, validated against an observed **8.0729%** base rate |
| Collections prioritisation | Ranked queue of 7,211 accounts |
| Power BI semantic layer | Star schema + DAX + page spec ([powerbi/BUILD_GUIDE.md](powerbi/BUILD_GUIDE.md)) |

---

## Key findings

**Ranking by severity reaches nothing.** 0% of recoverable value at 10% capacity, versus 79.8%.

**Recovery stops at 90 days.** Accounts 1–30 days late cure on their own 55–59% of the time. Past 90
days that falls to **4–7%**, and 85–98% simply stay put.

**Utilisation leads delinquency.** Cards that have gone over limit are **27× more likely** to have
been delinquent than cards kept under 30% utilisation — visible *before* a payment is missed.

**Demographics don't explain current delinquency.** Flat at **2.03%–2.36%** across every income type
and age band. Prioritisation must rest on behaviour and exposure.

**The early-warning framework is modest, and reported as such.** Best usable lift **1.80×**. Age alone
separates the outcome better than all five behavioural signals combined — though age is a protected
characteristic and largely unusable in a credit decision, which is precisely why the weaker
behavioural signals matter operationally.

### Negative results, kept deliberately

- **"Repeated credit enquiries" carries no signal** — 1.04× the base rate. A standard credit-risk
  intuition that does not hold in this data.
- **One optimisation failed.** The roll-rate sort could not be fixed by any index; `EXPLAIN` showed
  MySQL always materialises for buffered window functions. The response was to change the
  architecture instead.
- **One recommendation says not to act.** Older loan cohorts show 6.5× the delinquency of recent ones
  at equal age — but product mix, selection and censoring cannot be separated. Flagged for
  investigation, not presented as a conclusion.

---

## Validation

Every headline figure derived **three independent ways** — the analytical pipeline, a separate SQL
path against base tables, and pandas reading the original CSVs.

| Figure | Pipeline | Independent SQL | pandas |
|---|---:|---:|---:|
| Accounts at latest month | 1,040,632 | 1,040,632 | 1,040,632 |
| Active accounts | 327,101 | 327,101 | 327,101 |
| Delinquent (queue size) | 7,211 | 7,211 | 7,211 |
| Card exposure | ₹7,774.0M | ₹7,774.0M | ₹7,774.0M |
| Default base rate | 8.0729% | 8.0729% | 8.0729% |
| Split payments | 653,483 | 653,483 | 653,483 |

**20 reconciliation checks. All exact.**

## Performance

| Change | Before | After | Why |
|---|---:|---:|---|
| Covering index on the live book | 15.27s | **0.85s** | Index holds every column needed; table never touched |
| Materialising the transition matrix | 275.70s | **0.09s** | An unavoidable sort paid once instead of per run |
| Bulk load, 58.4M rows | — | **15.6 min** | `LOAD DATA LOCAL INFILE`, indexes built after |

---

## Limitations

1. **No calendar dates** — all time is relative to each customer's application. No calendar trends.
2. **No geography** — only an anonymised region rating of 1–3.
3. **No collections outcomes** — no contact records or recovery amounts. Cure rates are *observed
   natural transitions*, never a recovery forecast. **Nothing here claims that calling an account
   causes it to pay.**
4. **POS exposure is a proxy** — `CNT_INSTALMENT_FUTURE × AMT_ANNUITY`. ~85% of book exposure is
   estimated, and every account at the top of the queue is proxy-based.
5. **Survivorship** — 9.39% of accounts were *ever* delinquent; 2.20% are delinquent now.
6. **Small groups** — several striking rates rest on tiny denominators (n=67, n=22, n=5) and are
   always published with their counts.

Full registers: [assumptions, insights, learning log](docs/14_registers.md) ·
[executive summary](docs/13_executive_summary.md)

---

## Repository layout

```
database/
  schema.sql                 7 tables, types derived from measured value ranges
  staging_layer.sql          installment and account-month staging
  mart_layer.sql             pre-computed analytical mart
  loading/                   server setup, LOAD DATA, indexes, verification
  run_load.ps1 / run_sql.ps1 runners (credentials via MySQL's own store)
sql/
  RUN_ALL_KEY_QUERIES.sql    ← start here: 20 key queries, read-only, story order
  01_data_quality/           15 checks; the DPD evidence behind bucket design
  02_portfolio/              book, exposure, delinquency, borrower profile
  03_repayment/              installment-grain behaviour, signals
  05_vintage/                vintage curves + roll-rate matrix
  07_early_warning/          signal lift, recall, stacking, stability
  08_collections/            cure rates, priority tiers, the queue
  09_validation/             reconciliation + optimisation case studies
  10_powerbi/                semantic layer views
python/
  validate_independent.py    pandas cross-check, 9/9 pass
powerbi/
  BUILD_GUIDE.md             star schema, DAX, page-by-page spec
  export_for_powerbi.py      regenerates the CSV exports
docs/                        phase documentation, registers, executive summary, PDF report
RUNBOOK.md                   how to run everything in MySQL Workbench
```

**On the folder numbering:** the `sql/` folders follow the analytical modules, not the original phase
plan. `04_delinquency` and `06_roll_rate` were merged into `02`/`03` and `05` respectively, because
those analyses share a panel scan and splitting them would have meant scanning 13.8M rows twice.

---

## Getting the data

The raw CSVs (2.68 GB) are not in this repository — they are redistributed by Kaggle under
competition terms.

1. Create a Kaggle account and **accept the competition rules** at
   [kaggle.com/competitions/home-credit-default-risk](https://www.kaggle.com/competitions/home-credit-default-risk/rules)
   *(the download stays locked until you do — this is the step that silently fails)*
2. Download all files into `data/raw/`
3. Follow [RUNBOOK.md](RUNBOOK.md) §5 to build the database (~70 minutes)

Expected on disk: 10 files, 2,684,261,617 bytes total.

---

## Technologies

| Tool | Role |
|---|---|
| **MySQL 8.0** | The analytical engine — schema, bulk loading, all analysis, optimisation |
| **Python / pandas** | Memory-bounded profiling of 58M rows in 7.3 GB RAM, independent validation, load-script generation |
| **MySQL Workbench** | Interactive query development |
| **PowerShell** | Pipeline automation, timing, credential handling via MySQL's own store |
| **Power BI** | Decision layer (semantic model and spec) |
