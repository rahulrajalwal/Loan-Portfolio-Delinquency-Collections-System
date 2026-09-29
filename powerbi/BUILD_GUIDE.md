# Power BI Build Guide — Loan Portfolio & Collections Intelligence

**Design rule from Phase 1:** every page maps to a named stakeholder and a named
decision. If a visual serves nobody in that table, it does not go on the page.
This is what stops a dashboard becoming decoration.

---

## 1. Connecting

**Option A — live connection (preferred).**
Install **MySQL Connector/NET** (dev.mysql.com/downloads/connector/net/), then in
Power BI Desktop: *Get Data → MySQL database* → Server `localhost:3306`,
Database `loan_portfolio`. Choose **Import** (not DirectQuery — the mart is small
and Import gives far better performance).

Select exactly six objects:
`pbi_customer`, `pbi_account`, `pbi_queue`, `pbi_rollrate`, `pbi_vintage`, `pbi_signal`

**Option B — CSV fallback.** If the connector will not install, export each view
with the runner script and load the CSVs. Same model, same measures.

**Do not import the `stg_` or base tables.** They are 13M+ rows, none of it needed
at report grain, and importing them would undo the entire Phase 6 re-scoping.

---

## 2. The data model

```
                    pbi_customer  (356,255)   ← dimension
                          │ 1
             ┌────────────┼────────────┐
             │ *                       │ *
        pbi_account (1,040,632)   pbi_queue (7,211)

   pbi_rollrate (40)   pbi_vintage (432)   pbi_signal (11)   ← standalone
```

**Relationships to create:**

| From | To | Cardinality | Direction |
|---|---|---|---|
| `pbi_customer[SK_ID_CURR]` | `pbi_account[SK_ID_CURR]` | 1 → many | Single |
| `pbi_customer[SK_ID_CURR]` | `pbi_queue[SK_ID_CURR]` | 1 → many | Single |

`pbi_rollrate`, `pbi_vintage` and `pbi_signal` stay **unrelated**. They are
pre-aggregated at their own grain; joining them to anything would fan out.

**Why a star and not one wide table.** A flat table repeats every customer
attribute on every account row — the same fan-out error Phase 2 measured at
37.5×. On a star, `COUNTROWS(pbi_customer)` is correct by construction; on a flat
table you would need `DISTINCTCOUNT` everywhere and a plain `COUNT` would silently
over-count.

---

## 3. DAX measures

```dax
// ---------- PORTFOLIO ----------
Live Accounts = CALCULATE ( COUNTROWS ( pbi_account ), pbi_account[is_active] = TRUE() )

Total Exposure = CALCULATE ( SUM ( pbi_account[exposure] ), pbi_account[is_active] = TRUE() )

Exposure (M) = DIVIDE ( [Total Exposure], 1000000 )

Customers = DISTINCTCOUNT ( pbi_account[SK_ID_CURR] )

// ---------- DELINQUENCY ----------
Delinquent Accounts =
CALCULATE ( COUNTROWS ( pbi_account ),
    pbi_account[is_active] = TRUE(), pbi_account[is_delinquent] = TRUE() )

Delinquency Rate % = DIVIDE ( [Delinquent Accounts], [Live Accounts] ) * 100

NPA-equivalent Accounts =
CALCULATE ( COUNTROWS ( pbi_account ),
    pbi_account[is_active] = TRUE(), pbi_account[dpd] > 90 )

NPA Rate % = DIVIDE ( [NPA-equivalent Accounts], [Live Accounts] ) * 100

// [D3] materiality filter - delinquency once trivial balances are ignored
Material Delinquency Rate % =
DIVIDE (
    CALCULATE ( COUNTROWS ( pbi_account ),
        pbi_account[is_active] = TRUE(), pbi_account[is_material_delinquent] = TRUE() ),
    [Live Accounts] ) * 100

Delinquent Exposure (M) =
DIVIDE (
    CALCULATE ( SUM ( pbi_account[exposure] ),
        pbi_account[is_active] = TRUE(), pbi_account[is_delinquent] = TRUE() ),
    1000000 )

// ---------- OUTCOME (train customers only) ----------
Default Rate % =
CALCULATE ( AVERAGE ( pbi_customer[had_payment_difficulty] ) * 100,
            pbi_customer[data_source] = "train" )

Base Rate % = 8.0729      // measured, Phase 2/11, reproduced by three paths

Lift vs Base = DIVIDE ( [Default Rate %], [Base Rate %] )

Customers Scored =
CALCULATE ( COUNTROWS ( pbi_customer ), pbi_customer[data_source] = "train" )

// ---------- COLLECTIONS ----------
Queue Size = COUNTROWS ( pbi_queue )

Curable Value (M) = DIVIDE ( SUM ( pbi_queue[curable_value] ), 1000000 )

Queue Exposure (M) = DIVIDE ( SUM ( pbi_queue[exposure] ), 1000000 )

% of Curable Value =
DIVIDE ( SUM ( pbi_queue[curable_value] ),
         CALCULATE ( SUM ( pbi_queue[curable_value] ), ALL ( pbi_queue ) ) ) * 100

P1 Critical Accounts =
CALCULATE ( COUNTROWS ( pbi_queue ), pbi_queue[priority_tier] = "P1 critical" )

// Honesty flag: share of exposure that is the derived POS proxy, not a real balance
Proxy Exposure % =
DIVIDE (
    CALCULATE ( SUM ( pbi_account[exposure] ),
        pbi_account[is_active] = TRUE(), pbi_account[exposure_is_proxy] = 1 ),
    [Total Exposure] ) * 100

// ---------- ROLL RATE ----------
Cure Rate % =
CALCULATE ( SUM ( pbi_rollrate[roll_pct] ), pbi_rollrate[direction] = "cure" )

Forward Roll % =
CALCULATE ( SUM ( pbi_rollrate[roll_pct] ), pbi_rollrate[direction] = "forward roll" )

Transitions Observed = SUM ( pbi_rollrate[transitions] )
```

---

## 4. Page specifications

### PAGE 1 — Portfolio Health
**Stakeholder:** Portfolio / Business Head · **Decision:** where to grow, where to pull back

| # | Business question | Metric | Source | Visual | Why this visual | Insight | Action |
|---|---|---|---|---|---|---|---|
| 1.1 | How big is the live book? | `Live Accounts`, `Exposure (M)`, `Customers` | `pbi_account` | KPI cards | A single number needs no chart | 327,101 accounts, ₹52,218M | Baseline for every other page |
| 1.2 | What is it made of? | Accounts by product × status | `pbi_account` | Stacked bar | Composition of a whole | POS 25% active vs CARD 87% — different lifecycles | Do not read the two products on one scale |
| 1.3 | Is exposure concentrated? | Exposure by decile | `pbi_account` | Pareto (bar + cumulative line) | Pareto is *the* concentration visual | Top decile = 51.55% of exposure | Exposure-weight everything downstream |
| 1.4 | Does delinquency differ by segment? | `Delinquency Rate %` by `income_type`, `age_band` | `pbi_customer` → `pbi_account` | Bar with reference line at portfolio rate | Reference line makes "flat" visible | **Flat: 2.03–2.36% everywhere** | Do not segment collections demographically |
| 1.5 | How much exposure is estimated? | `Proxy Exposure %` | `pbi_account` | KPI card, amber | Honesty belongs on the page, not the appendix | ~85% is the POS proxy | Caveat every exposure figure |

### PAGE 2 — Delinquency & Repayment
**Stakeholder:** Credit Risk Manager · **Decision:** tighten or loosen underwriting

| # | Business question | Metric | Source | Visual | Why | Insight | Action |
|---|---|---|---|---|---|---|---|
| 2.1 | Where is the book on the DPD ladder? | Accounts + exposure by `bucket_reporting` | `pbi_account` | Clustered bar, dual measure | Counts and money must be seen together | 360+ has 1,369 accounts, ₹0.2M | Never rank by severity alone |
| 2.2 | Is severity where the money is? | Mean exposure by bucket | `pbi_account` | Line over bucket | Shows the inversion in one shape | Peaks at 61–90 (371,791), collapses to 179 at 360+ | The core collections argument |
| 2.3 | Does delinquency survive materiality? | `Delinquency Rate %` vs `Material Delinquency Rate %` | `pbi_account` | Butterfly / paired bar | Direct comparison of two definitions | Card: 1,317 → 307 (23% survive) | Filter the queue by materiality |
| 2.4 | Does utilisation lead delinquency? | Ever-delinquent % by `utilisation_band` | `pbi_account` | Column, ordered | Ordered bands show monotonicity | 1.33% → 35.82%, a 27× spread | Utilisation as an early trigger |
| 2.5 | Does repayment history track the outcome? | `Default Rate %` by repayment band | `pbi_customer` | Column + `Base Rate %` line | The line is the benchmark | Monotonic 5.98% → 14.25% | Feed into origination policy |

### PAGE 3 — Vintage & Roll Rate
**Stakeholder:** Credit Risk Manager · **Decision:** forecast NPA formation

| # | Business question | Metric | Source | Visual | Why | Insight | Action |
|---|---|---|---|---|---|---|---|
| 3.1 | How do accounts move between buckets? | `roll_pct` | `pbi_rollrate` | **Matrix heatmap**, from × to | A transition matrix *is* a matrix | Diagonal dominance past 90 days | Read momentum, not level |
| 3.2 | Where does curing stop? | `Cure Rate %`, `Forward Roll %` by bucket | `pbi_rollrate` | Line, two series | Crossing lines show the cliff | **Cure 57% → 5% past 90 days** | Concentrate effort before day 90 |
| 3.3 | Are cells thick enough to trust? | `Transitions Observed` | `pbi_rollrate` | Data labels on 3.1 | Phase 5 found sparse middle buckets | 31–90 rests on 6.6k–12.6k | Publish counts beside every rate |
| 3.4 | Do cohorts differ at equal age? | `delinq_pct` by `months_on_book`, series = `cohort` | `pbi_vintage` | Multi-line, X = MOB | Vintage curves must align on age | 6.5× gradient at MOB 6 | Flag for investigation, not conclusion |

### PAGE 4 — Collections Prioritisation
**Stakeholder:** Collections Manager · **Decision:** who to work today

| # | Business question | Metric | Source | Visual | Why | Insight | Action |
|---|---|---|---|---|---|---|---|
| 4.1 | How big is the queue and what is at stake? | `Queue Size`, `Queue Exposure (M)`, `Curable Value (M)`, `P1 Critical Accounts` | `pbi_queue` | KPI cards | Orientation | 7,211 accounts, ₹285M curable | Sizing for capacity planning |
| 4.2 | **Does ranking by value beat ranking by DPD?** | Cumulative `% of Curable Value` | `pbi_queue` | **Dual cumulative line** | Two curves, one obviously better | **Top 10%: 79.8% vs 0.0%** | **The headline of the whole project** |
| 4.3 | How does the queue tier out? | Accounts, exposure, `% of Curable Value` by `priority_tier` | `pbi_queue` | Table with data bars | Operational lists want tables | P1+P2 = 20% of queue, 96.3% of value | Work P1 first |
| 4.4 | Which accounts, specifically? | Account detail | `pbi_queue` | Table, drill-through from 4.3 | The deliverable is a list | 7,211 inspectable rows | Hand to the collections team |
| 4.5 | How good is the early-warning framework? | `lift`, `recall_pct` | `pbi_signal` | Scatter, lift × recall, sized by `flagged` | Shows the trade-off honestly | Sharp signals ≈1% coverage; broad ones ≈1.0 lift | Report the limits, don't hide them |

---

## 5. Build-time checks

After building, these must match exactly. If they don't, a relationship or filter is wrong.

| Measure | Expected |
|---|---:|
| `Live Accounts` | 327,101 |
| `Exposure (M)` | 52,218.2 |
| `Delinquent Accounts` | 7,211 |
| `Delinquency Rate %` | 2.2045 |
| `NPA Rate %` | 0.5124 |
| `Queue Size` | 7,211 |
| `P1 Critical Accounts` | 1,255 |
| `Default Rate %` (no filter, train) | 8.0729 |
| `Customers Scored` | 307,511 |

---

## 6. Design constraints carried from earlier phases

1. **Every rate carries its count.** Phase 5 found `Unemployed` defaulting at 36.36% on n=22. Rates without denominators mislead.
2. **Never sum POS and CARD exposure without flagging the proxy.** POS is derived; CARD is a real balance.
3. **No geography page.** There is no state or city in this data. `region_rating` (1–3) is anonymised and is not a map.
4. **No calendar-time trend page.** All time is relative to each customer's application date.
5. **Nothing labelled "expected recovery."** Cure rates are observed natural transitions. There is no intervention data.
