# Phase 0-A — Indian Lending Dataset Investigation

**Purpose:** Establish, with evidence, whether a real India-specific lending dataset can support the
Loan Portfolio, Delinquency & Collections Intelligence System — before any fallback is considered.

**Date:** 2026-09-04
**Method:** Source-family sweep → provenance verification → structural sufficiency test → module-level
support mapping.

**Evidence standard used:** a dataset is only accepted as "Indian" if the *observations* are verifiably
Indian, not merely the host site or the title. A dataset is only accepted as "real" if provenance is
documented. Synthetic data is disqualified as a core dataset by project rule.

---

## 1. The sweep — every source family searched

| # | Source family | Specific sources checked | Found | Verdict |
|---|---|---|---|---|
| 1 | **RBI statistical publications** | BSR-1A / BSR-1B (Annual & Quarterly), Sectoral Deployment of Bank Credit, Financial Stability Report, Trend & Progress | Rich, authoritative statistics | **Aggregated only.** BSR-1A is *collected* at borrowal-account level but **published** by bank × district × population group × occupation × organisation. No borrower ID, no time series per account. |
| 2 | **RBI data portals** | DBIE → CIMS (`data.rbi.org.in`, migrated Jun 2024) | Excel/CSV downloads, 7 subject areas | **Time-series aggregates.** No unit-level/microdata release channel found. |
| 3 | **RBI Public Credit Registry** | PCR High Level Task Force report; Dvara Research analysis | Borrower-level *by design* | **Never publicly released.** Task force flagged it needs enabling legislation; Dvara notes privacy/proportionality problems with borrower-level access. Regulatory infrastructure, not open data. |
| 4 | **data.gov.in (OGD Platform)** | Keyword sweeps: RBI, KCC, loan, agriculture credit, Mudra | Written-off loan recovery 2017-22; KCC agri credit 2019-24; state-wise agri loan disbursement; NABARD account counts | **All year × state × scheme aggregates.** Zero account-level resources found. |
| 5 | **Other GoI / PSU** | NABARD, SIDBI, MoSPI Compendium of Datasets, Indiastat | Scheme performance, credit flow | Aggregated |
| 6 | **Indian academic / research repositories** | Harvard Dataverse (J-PAL, IndiaAccess), IFMR CMF, ISB Centre for Analytical Finance, ISB India Data Portal | J-PAL Hyderabad microfinance RCT (Spandana) — **household survey** data, ~2,800 households; ISB CAF holds only Bloomberg/Refinitiv/Morningstar/MCA subscriptions | **Not lender ledgers.** RCT data measures household borrowing/consumption, not an institution's loan book with monthly performance. Scale (thousands of households) also fails the portfolio test. |
| 7 | **Indian academic work using real MFI data** | IIT Madras M.Tech thesis, *Loan Default Prediction on Indian MFI Dataset* (V. Sai Krishna, 2022) | Real anonymised Indian MFI data: credit-bureau features + customer-level + loan-level features from multiple partner institutions | **Proprietary.** Obtained through collaboration with **Kaleidofin Private Limited** under supervision by Kaleidofin staff. Not downloadable. **This is the pattern:** Indian loan-level data reaches researchers through NDAs with lenders, never through open release. |
| 8 | **Credit bureaus** | TransUnion CIBIL (incl. MSME Pulse), CRIF High Mark, Equifax India, Experian India | Delinquency *reports* and indices | **Published as PDF reports.** Underlying data is commercially licensed and governed by CICRA 2005. |
| 9 | **Microfinance industry bodies** | MFIN Micrometer, Sa-Dhan Bharat Microfinance Report, MIX Market | PAR30/PAR90, portfolio, disbursement | **MFI-level aggregates.** |
| 10 | **Securitisation / ABS disclosure** | RBI STC framework, SEBI securitised-debt listing & periodic disclosure norms (effective 31 Mar 2026) | Loan-level and pool-level reports **are mandated — to investors** | **No public loan-level repository.** India has no equivalent of the European DataWarehouse or the RBA securitisation repository. SEBI requires pool level, tranche level and "select loan information" to listed-instrument holders. |
| 11 | **Indian P2P / NBFC-P2P** | Faircent, Lendbox, i2iFunding, LiquiLoans; RBI NBFC-P2P norms (2017, revised 2024) | Platforms must disclose *losses borne by lenders*; Faircent reports 6–7% NPA | **Aggregate percentages on websites.** No platform publishes a downloadable loan book (unlike LendingClub in the US). RBI issued a questionnaire in Jan 2025 precisely because disclosures were lacking. |
| 12 | **Kiva (crowdfunded lending, incl. India)** | Kiva Data Snapshots (`build.kiva.org`), Kiva help centre | `lenders`, `loans`, `loans_lenders` files; status values `defaulted` / `in_repayment` / `paid` | **India specifically excluded from repayment tracking.** Kiva states it does **not** provide delinquency/default/risk data for India Field Partners (fields set to "N/A"): RBI foreign-funding rules require a 3-year minimum term, partners hold funds for the full term, and "Kiva will not provide regular repayment updates during India loan terms." **Fatal for a repayment project.** |
| 13 | **Indian hackathons** | Analytics Vidhya DataHack (LTFS FinHack, Loan Prediction III, Jobathon), Indian bank/NBFC challenges | LTFS vehicle loan (see §2.1); Loan Prediction III (~614 rows) | Flat single tables; no repayment panel |
| 14 | **General repositories** | Kaggle, GitHub, Hugging Face, Mendeley Data, Zenodo, figshare | Numerous "Indian loan" uploads | Either tiny, name-lists, undocumented re-uploads, or not verifiably Indian (see §2.4) |

---

## 2. The serious Indian candidates — provenance and structure

### 2.1 LTFS / L&T Financial Services vehicle loan  ← strongest genuine Indian candidate

| Attribute | Finding |
|---|---|
| **Provenance** | L&T Financial Services (a real Indian NBFC) via Analytics Vidhya "DataScience FinHack". **Genuinely Indian** — verified by India-specific fields, not by title. |
| **India markers** | `State_ID`, `branch_id`, `Current_pincode_ID`, `Aadhar_flag`, `PAN_flag`, `VoterID_flag`, `Driving_flag`, `Passport_flag`, `PERFORM_CNS.SCORE` (CIBIL-style bureau score), `PERFORM_CNS.SCORE.DESCRIPTION` |
| **Files** | `train.csv`, `test.csv`, `data_dictionary.csv`, `sample_submission.csv` — **one data table** |
| **Scale** | ~233k train / ~112k test rows, ~41 columns *(per published documentation; not independently verified — we have not downloaded it)* |
| **Target** | *"the probability of loanee/borrower defaulting on a vehicle loan in the first EMI (Equated Monthly Instalments) on the due date"* |
| **Time fields** | `Date.of.Birth`, `DisbursalDate` — **real calendar dates**, but disbursals span only a narrow window |
| **Credit history** | Present **only as pre-aggregated bureau counts**: `PRI.NO.OF.ACCTS`, `PRI.ACTIVE.ACCTS`, `PRI.OVERDUE.ACCTS`, `PRI.CURRENT.BALANCE`, `SEC.*` equivalents, `NEW.ACCTS.IN.LAST.SIX.MONTHS`, `DELINQUENT.ACCTS.IN.LAST.SIX.MONTHS`, `AVERAGE.ACCT.AGE`, `CREDIT.HISTORY.LENGTH`, `NO.OF_INQUIRIES` |
| **Repayment history table** | **None.** No installment records, no monthly account status, no DPD series. |
| **Licensing** | Hackathon terms; redistribution on a public GitHub repo is ambiguous |

**What it fundamentally is:** an *application-scoring* dataset. It captures the borrower at one instant
and one binary outcome. It is not a portfolio ledger.

### 2.2 Kiva India

Real, public, downloadable — and **structurally disqualified for India specifically**. Kiva's own help
documentation states delinquency/default/risk fields are "N/A" for India Field Partners because RBI
foreign-funding regulation forces a 3-year minimum term during which partners hold repayments and
Kiva publishes no repayment updates. A repayment/delinquency project cannot be built on data whose
publisher explicitly does not track repayment.

### 2.3 RBI / data.gov.in family

Zero account grain. Excellent as **README context** — India's retail credit growth, GNPA trends,
CRIF High Mark's reported rise in small-ticket delinquency — but the project cannot be built on it.

### 2.4 Kaggle "Indian" loan uploads

| Dataset | Problem |
|---|---|
| `Loan_Prediction_India`, Analytics Vidhya Loan Prediction III | ~614 rows. Fails scale. |
| `India Wilful Loan Defaulters` | A **list of defaulter names and amounts**. No repayment behaviour, no account history. |
| `Indian Banks Loan Dataset` | Undocumented re-upload; provenance not established |
| `Credit/Loan Dataset - Rural India` | Description not retrievable; provenance unverified |
| `NBFI Vehicle Loan repayment Dataset` | "NBFI" is Bangladeshi usage; **Indian-ness not verifiable**. Project rule forbids assuming from a title. |
| `Microfinance Loan` / `Microfinance Bank Loan` | Country not established; several appear synthetic |

None survives the "real + documented + verifiably Indian + sufficient" test.

---

## 3. Module-level support matrix

The question that decides the project: **which of our 13 analytical modules does each candidate
actually support?**

| # | Module | LTFS (India) | Kiva India | RBI / data.gov.in | Indian Kaggle sets | Home Credit |
|---|---|:--:|:--:|:--:|:--:|:--:|
| M1 | Portfolio composition & exposure baseline | ◐ origination only | ◐ | ✖ | ✖ | ✔ |
| M2 | Multi-table data-quality forensics | ◐ single table | ◐ | ✖ | ✖ | ✔ |
| M3 | Relational model: PK/FK, grain, fan-out control | ✖ | ◐ | ✖ | ✖ | ✔ |
| M4 | Repayment behaviour at installment grain | ✖ | ✖ | ✖ | ✖ | ✔ |
| M5 | DPD measurement & delinquency bucketing | ✖ | ✖ | ✖ | ✖ | ✔ |
| M6 | Delinquency concentration by segment | ◐ first-EMI only | ✖ | ✖ | ✖ | ✔ (no geography) |
| M7 | Roll-rate / state transitions | ✖ | ✖ | ✖ | ✖ | ✔ |
| M8 | Vintage / months-on-book curves | ✖ | ✖ | ✖ | ✖ | ✔ (relative time) |
| M9 | Cohort comparison | ◐ narrow window | ✖ | ✖ | ✖ | ✔ (relative cohorts) |
| M10 | Early-warning signal framework | ◐ bureau aggregates | ✖ | ✖ | ✖ | ✔ |
| M11 | Signal validation vs observed outcome | ✔ | ✖ | ✖ | ✖ | ✔ |
| M12 | Collections prioritisation queue | ✖ | ✖ | ✖ | ✖ | ✔ |
| M13 | Power BI decision layer (4 pages) | ◐ ~1–2 pages | ✖ | ✖ | ✖ | ✔ |
| | **Fully supported** | **1 / 13** | **0 / 13** | **0 / 13** | **0 / 13** | **13 / 13** |
| | **Partly supported** | 6 | 3 | 0 | 0 | 0 |

✔ full · ◐ partial · ✖ not possible

**The best real Indian dataset supports one of thirteen modules fully.** The project as scoped —
delinquency, roll rate, vintage, collections prioritisation — is not buildable on public Indian data.

---

## 4. Why the gap exists (this is structural, not a search failure)

Four independent mechanisms, each evidenced:

1. **Publication mandate is aggregate.** RBI collects BSR-1A at borrowal-account level but publishes
   it grouped. The granularity is destroyed at the publication step by design.
2. **No enabling legislation for borrower-level release.** The PCR task force concluded the registry
   needs statutory backing; Dvara Research argues borrower-level access without controls may fail a
   privacy proportionality test.
3. **CICRA 2005 + data-localisation rules.** Credit information must be stored and processed within
   India and shared only with specified entities — which forecloses open publication by bureaus.
4. **No public securitisation loan-level repository.** RBI/SEBI mandate loan-level reporting **to
   investors**, not to the public. India has no European DataWarehouse or RBA-style repository.

Consequence: real Indian loan-level data reaches analysts **only through institutional partnership**
— exactly as the IIT Madras / Kaleidofin thesis demonstrates. It is not obtainable for an
independent student project.

**This is itself a defensible interview answer**, not an excuse. It shows the candidate investigated
the data landscape rather than reaching for the first Kaggle file.

---

## 5. Verdict

Applying the project's own decision framework:

- **STEP 1 — Search for real Indian data:** done, 14 source families, documented above.
- **STEP 2 — Test sufficiency:** done, module matrix in §3.
- **STEP 3 — Prefer Indian if sufficient:** the condition **fails**. Best candidate: 1/13 modules.
- **STEP 4 — Do not force weak Indian data:** LTFS is missing repayment history, monthly panel, DPD,
  account relationships and any active-book concept. Forcing it would require abandoning six of the
  project's seven analytical pillars.
- **STEP 5 — Fall back to the strongest real non-Indian dataset, explicitly:** → **Home Credit
  Default Risk** (see [00_phase0_dataset_selection.md](00_phase0_dataset_selection.md) §3–§7).

### What goes in the README (honest positioning)

> Real India-specific lending data was investigated first across RBI publications and portals, the
> Public Credit Registry proposal, data.gov.in, credit bureaus, microfinance industry bodies,
> securitisation disclosure regimes, Indian P2P platforms, academic repositories and public dataset
> hosts. India publishes rich *statistics about* lending but, for statutory and privacy reasons, does
> not publish *records of* individual loans. The strongest genuine Indian candidate — an NBFC vehicle-
> loan application dataset — is a single flat table with a first-EMI default flag and no repayment
> history, supporting one of this project's thirteen analytical modules. The project therefore uses a
> real, anonymised, multi-table consumer-lending dataset (Home Credit) and **makes no claim that the
> data represents India.** The analytical framework — portfolio monitoring, DPD bucketing, roll
> rates, vintage curves and collections prioritisation — is the standard toolkit of retail lending
> analytics in any market, India included.

### What is NOT claimed
- That the data is Indian
- That any finding describes the Indian credit market
- That Indian data was unavailable because it does not exist — it exists; it is not *public*
