# Executive Summary
## Loan Portfolio, Delinquency & Collections Intelligence System

**Prepared by:** Rahul Meena · **Date:** 2026-09-08
**Data:** Home Credit Default Risk — 58.4M rows across 7 tables, loaded to MySQL 8.0
**Scope:** 1,040,632 credit accounts · 356,255 borrowers · 327,101 accounts live

> **Data provenance.** This is real, anonymised consumer-lending data published by
> Home Credit Group. Its country of origin is not disclosed and **no claim is made
> that it represents India or any named market.** Real India-specific lending data
> was searched for first across 14 source families in three separate rounds; it
> exists but is not public, for statutory and privacy reasons. See
> `00a_india_dataset_investigation.md`.

---

## 1. The business problem

A consumer lender holds an active book of POS/cash loans and revolving credit
cards, alongside a rich behavioural history of each borrower's internal and
external credit. Two questions had no evidence-based answer:

1. **Of the accounts on our books now, which are in repayment stress, how fast are
   they deteriorating, and which deserve limited collections capacity first?**
2. **Do those same stress signals, observed when a customer applies for new
   credit, identify borrowers who go on to have payment difficulty?**

---

## 2. Key findings

### 2.1 Ranking collections by severity destroys value

Of the 7,211 delinquent accounts in the live book:

| Bucket | Accounts | Exposure | Observed cure rate | Share of curable value |
|---|---:|---:|---:|---:|
| 1–30 days | 5,163 | ₹465.7M | 55.4% | **91.2%** |
| 31–90 days | 372 | ₹101.2M | 24.5% | 8.4% |
| 91–360 days | 307 | ₹18.2M | 6.0% | 0.4% |
| **360+ days** | **1,369** | **₹0.2M** | 2.0% | **0.0%** |

The 360+ bucket is **19% of the queue by headcount and 0.0% by value** — mean
balance ₹179, on accounts averaging 1,573 days past due.

Ranking the same 7,211 accounts two ways, then measuring how much curable value
each ordering reaches:

| Capacity worked | Ranked by curable value | Ranked by DPD |
|---:|---:|---:|
| 5% | **57.6%** | 0.0% |
| **10%** | **79.8%** | **0.0%** |
| 20% | **96.3%** | 0.0% |

### 2.2 Curing effectively stops at day 90

Month-to-month transitions across 12.5M observed account-month pairs:

| Bucket | Cure | Stays | Rolls forward |
|---|---:|---:|---:|
| 1–30 | **55–59%** | 37–40% | 4.1–4.6% |
| 31–90 | 23–32% | 40–41% | **28–36%** |
| 91–360 | **4.3–6.8%** | 85–86% | 8.3–9.3% |
| 360+ | 1.7–2.4% | **98%** | — |

Past 90 days the accounts are effectively absorbing: 85–98% stay where they are.

### 2.3 Credit utilisation leads delinquency

Card accounts, by peak utilisation:

| Peak utilisation | Accounts | Ever delinquent |
|---|---:|---:|
| 0–30% | 32,602 | **1.3%** |
| 60–90% | 6,408 | 16.0% |
| 90–100% | 8,774 | 18.4% |
| **Over limit** | **38,064** | **35.8%** |

A **27× spread**, monotonic. 42% of active cards have been over limit.

### 2.4 Demographics do not explain current delinquency — but do predict new-loan default

| Lens | Spread across segments |
|---|---|
| Delinquency on existing accounts | **Flat: 2.03%–2.36%** across every income type and age band |
| Payment difficulty on a *new* loan | **4.5%–11.2%** by age; 5.4%–9.6% by income type |

The same borrower attributes are uninformative for one outcome and strongly
informative for the other.

### 2.5 The early-warning framework is real but modest

A transparent five-rule framework, validated against an observed 8.07% base rate:

| Threshold | Customers flagged | Default rate | Lift | Defaults caught |
|---|---:|---:|---:|---:|
| ≥1 signal | 49,368 (16.1%) | 10.29% | 1.27× | 20.5% |
| ≥3 signals | 2,963 (1.0%) | 14.55% | **1.80×** | 1.7% |

Scores of 1 and 2 are statistically indistinguishable (10.020% vs 10.030%).
**Age alone separates the outcome more strongly than the whole framework.**

---

## 3. Risk areas

| # | Risk area | Evidence |
|---|---|---|
| 1 | **Exposure concentration** — top 10% of accounts hold 51.6% of exposure; top 20% hold 72% | Phase 6 decile analysis |
| 2 | **The 31–90 window** — where cure collapses and forward roll peaks (28–36%) | Phase 8 roll rates |
| 3 | **Over-limit card population** — 38,064 accounts (42% of active cards), 35.8% ever delinquent | Phase 7 R5 |
| 4 | **Deteriorating accounts** — 11,896 accounts, 56.3% currently delinquent, 1.57× default on new credit | Phase 7 R6 |
| 5 | **Shortfall behaviour** — customers with 6+ short installments default at 49.3% (6.1×), though only 67 such customers exist | Phase 7 R3 |

---

## 4. High-priority segments

Priority is **behavioural, not demographic** — finding 2.4 is the reason.

| Tier | Accounts | % of queue | Curable value | Share of value |
|---|---:|---:|---:|---:|
| **P1 critical** — top-quintile value **and** deteriorating | 1,255 | 17.4% | ₹249.9M | **87.8%** |
| **P2 high** — top-quintile value | 188 | 2.6% | ₹24.3M | 8.5% |
| P3 medium — material, curable bucket | 2,755 | 38.2% | ₹5.5M | 1.9% |
| P4 low / monitor | 1,644 | 22.8% | ₹5.1M | 1.8% |
| **P5 recovery — not a collections case** | 1,369 | 19.0% | ₹0.0M | 0.0% |

**P1 + P2 = 20% of the queue holding 96.3% of curable value.**

Cross-checked against the one outcome available: P1 borrowers show a 25.8%
observed default rate (3.20× base) versus 8.6% for P5 — a monotonic gradient the
tiering never optimised for.

---

## 5. Collections opportunity

- **₹285M in cure-weighted exposure** sits in the live delinquent book.
- **₹274M of it (96.3%) is reachable by working 1,443 accounts** — P1 and P2.
- Re-ranking from DPD to cure-weighted exposure moves value reached at 10%
  capacity from **0.0% to 79.8%**.

**This is a measure of where recoverable value is concentrated. It is not a
forecast of recovery.** Cure rates are observed *natural* month-to-month
transitions. This dataset contains no contact records, promises to pay, or
recovery amounts, so no claim about intervention effectiveness is made anywhere.

---

## 6. Recommendations

Each follows: **data → observation → analysis → evidence → interpretation → recommendation.**

### R1 — Rank the collections queue by cure-weighted exposure, not by days past due
- **Observation:** mean exposure peaks at 61–90 DPD (₹371,791) and collapses to ₹179 at 360+.
- **Evidence:** DPD-ranking reaches 0.0% of curable value at 10% capacity; value-ranking reaches 79.8%.
- **Interpretation:** severity and money at risk are close to *inversely* related in this book.
- **Recommendation:** adopt `exposure × observed cure rate` as the queue's sort key. **Potential impact: substantially more curable value reached per unit of capacity.** Quantifying recovery gain is not possible without intervention data.

### R2 — Move the 360+ population out of collections and into recovery
- **Observation:** 1,369 accounts, mean balance ₹179, mean 1,573 days past due, 2.0% observed cure.
- **Interpretation:** these are written-off or settled balances with a still-running DPD counter. Working them consumes 19% of queue headcount for 0.0% of value.
- **Recommendation:** reclassify as a recovery/write-off population with separate handling and reporting. Do not include in collections capacity planning.

### R3 — Concentrate intervention before day 90
- **Evidence:** cure falls from 55–59% (1–30) to 23–32% (31–90) to 4.3–6.8% (91–360). Forward roll peaks at 28–36% in the 31–90 window.
- **Interpretation:** the 31–90 bucket is where outcomes are still movable and where deterioration is fastest.
- **Recommendation:** weight capacity toward 1–30 and 31–90. Treat crossing day 90 as an escalation trigger, since **observed** cure beyond it is under 7%.

### R4 — Use card utilisation as an early trigger
- **Evidence:** ever-delinquent rises monotonically 1.3% → 35.8% from lowest to highest utilisation band; 38,064 active cards are over limit.
- **Interpretation:** utilisation is a *leading* indicator; DPD is *lagging*. Utilisation is elevated before payments are missed.
- **Recommendation:** monitor sustained utilisation above 90% as a pre-delinquency watch trigger. **Association only** — high utilisation is not established as a cause of delinquency.

### R5 — Do not segment collections demographically
- **Evidence:** delinquency on existing accounts is flat at 2.03%–2.36% across every income type and age band tested.
- **Interpretation:** demographic attributes carry no usable information about *who is currently delinquent*, whatever they say about origination risk.
- **Recommendation:** build collections prioritisation on behaviour and exposure only. This also reduces fair-lending exposure.

### R6 — Apply a materiality filter to card delinquency
- **Evidence:** only 23% of card delinquency survives the tolerance-adjusted DPD measure (1,317 → 307), versus 60% for POS (5,894 → 3,523).
- **Interpretation:** a large share of reported card delinquency is trivial residual balances.
- **Recommendation:** report card delinquency on both measures. Filter the working queue by materiality; keep the unfiltered figure for regulatory-style reporting.

### R7 — Treat the early-warning framework as a supplement, not a gate
- **Evidence:** best usable lift 1.80× at 1.0% coverage; scores 1 and 2 indistinguishable; a customer under 30 with **zero** signals (11.20%) is riskier than one aged 60+ with **two or more** (7.90%).
- **Interpretation:** the behavioural signals carry real information — the gradient holds in every segment — but less than age alone.
- **Recommendation:** use as a **referral trigger alongside** existing scoring, never as a standalone decline rule. Revisit if broader behavioural coverage becomes available; the binding constraint is coverage, not signal quality.

### R8 — Investigate the vintage gradient; do not act on it yet
- **Observation:** delinquency at equal age (MOB 6) falls monotonically from 4.11% (oldest cohort) to 0.63% (most recent) — a 6.5× gradient.
- **Interpretation:** *consistent with* improving origination quality, but **three confounds cannot be separated**: product-mix shift, selection (every customer here returned for new credit), and thinning observation at higher MOB for recent cohorts.
- **Recommendation:** flag for investigation with calendar-dated origination data. **This finding does not support a conclusion that underwriting improved.**

---

## 7. Limitations

| # | Limitation | Consequence |
|---|---|---|
| 1 | **No calendar dates.** All time is relative to each customer's application date | No calendar trends; cohorts are origination-recency bands, not quarters |
| 2 | **No geography.** Only an anonymised region rating (1–3) | No state/city analysis, no mapping |
| 3 | **No collections outcomes.** No contact, promise-to-pay or recovery records | Cannot measure intervention effectiveness. Prioritisation only |
| 4 | **POS exposure is a proxy** — `CNT_INSTALMENT_FUTURE × AMT_ANNUITY`, includes interest | ~85% of book exposure is estimated, not measured. **Every account in the top 15 of the queue is proxy-based** |
| 5 | **Snapshot is relative-time.** "Latest observed month" differs in real time per customer | Not a common as-of date |
| 6 | **Thin middle buckets.** 31–90 transitions rest on 6,668 (card) / 12,613 (POS) pairs | Roll rates through that bucket are less stable; counts published everywhere |
| 7 | **Small high-signal groups.** 6+ shortfalls: n=67. Three-signal cell: n=5 | Striking rates on tiny denominators; never quoted alone |
| 8 | **`bureau_balance` dropped** (27.3M rows) as duplicative of internal panels | No external monthly roll-rate module |
| 9 | **Survivorship in the live book.** 9.39% of accounts were ever delinquent; 2.20% are now | Book health overstated relative to lifetime experience |
| 10 | **Outcome is application-time.** `TARGET` = difficulty on a *new* loan, not on the observed accounts | Validation is directional, not a same-account default measure |

---

## 8. Confidence in the numbers

Every headline figure was derived **three independent ways** — the project pipeline,
a separate SQL path against base tables, and pandas against the original CSVs.

| Check | Pipeline | Independent SQL | pandas |
|---|---:|---:|---:|
| Accounts at latest month | 1,040,632 | 1,040,632 | 1,040,632 |
| Active accounts | 327,101 | 327,101 | 327,101 |
| Delinquent (queue size) | 7,211 | 7,211 | 7,211 |
| CARD exposure | ₹7,774.0M | ₹7,774.0M | ₹7,774.0M |
| `TARGET` base rate | 8.0729% | 8.0729% | 8.0729% |
| Split payments (F1) | 653,483 | 653,483 | 653,483 |
| POS 1–30 → 31–90 | 7,291 | 7,291 | 7,291 |

**11 SQL reconciliation checks and 9 pandas checks: all exact.**
