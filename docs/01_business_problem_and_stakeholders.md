# Phase 1 — Business Problem, Scope & Stakeholders

**Status:** ✅ **APPROVED 2026-09-04.**
**Date:** 2026-09-04

**Decisions taken:**
- **[D1] Framing C approved** — the system answers two questions from one behavioural evidence base:
  who to collect from now, and who to watch at origination.
- **[D2] Deferred to Phase 5 by decision.** Bucket boundaries will be set **after** inspecting the
  actual `SK_DPD` distribution, rather than adopted in advance. Rationale: a boundary chosen before
  seeing the data cannot be defended beyond "it is the convention". We will still report how our
  empirical boundaries compare to the RBI SMA/NPA grid, so the regulatory framing remains available
  as a reference point — but the choice will be evidence-led.
- **[D3] Deferred to Phase 5** — `SK_DPD` vs `SK_DPD_DEF`.

---

## Part A — The vocabulary

You cannot write a defensible lending business problem without these nine terms. Each is taught here
in the form: *what it is → why it matters → worked example → where it lives in our data → likely
interview question.*

---

### A1. Principal, interest, and the installment (EMI)

**What.** The **principal** is the money actually lent. **Interest** is the price of borrowing it. An
**installment** (in India, EMI — Equated Monthly Installment) is the fixed periodic payment that
repays both. Early installments are mostly interest; later ones mostly principal. That split is the
*amortisation schedule*.

**Why it matters.** Two loans with identical EMIs can carry very different remaining principal. If you
measure "how much money is at risk" using the EMI, you get the wrong answer. Outstanding principal is
what a lender actually loses.

**Worked example.** ₹1,00,000 for 12 months at 12% p.a. → EMI ≈ ₹8,885. Total paid ≈ ₹1,06,620, so
interest ≈ ₹6,620. After 6 payments the borrower has paid ₹53,310 but still owes roughly ₹51,000 of
principal — *not* ₹50,000, because early payments were interest-heavy.

**In our data.** `previous_application.AMT_CREDIT` (amount lent), `AMT_ANNUITY` (the installment),
`CNT_PAYMENT` (number of installments). `installments_payments.AMT_INSTALMENT` is what was due on a
given installment; `AMT_PAYMENT` is what actually arrived.

**Interview question.** *"A borrower has paid half their EMIs. Have they repaid half the principal?"*
No — less than half, because early installments are interest-weighted.

---

### A2. Exposure

**What.** The money the lender stands to lose on an account **right now** — outstanding principal plus
any accrued unpaid dues. Not the original loan amount, and not the EMI.

**Why it matters.** Exposure is the weight in every risk calculation. A 90-days-past-due account with
₹4,000 left owing is a smaller problem than a 30-days-past-due account with ₹4,00,000 outstanding.
Collections capacity is finite, so it follows exposure, not just severity.

**Worked example.** Two delinquent accounts: A is 95 DPD with ₹5,000 outstanding; B is 35 DPD with
₹3,00,000 outstanding. Ranked by DPD alone, you call A first. Ranked by money at risk, B is 60× more
important.

**In our data.**
- Credit cards → **direct**: `credit_card_balance.AMT_BALANCE` (also `AMT_TOTAL_RECEIVABLE`).
- POS/cash loans → **derived**: `POS_CASH_balance.CNT_INSTALMENT_FUTURE` × `previous_application.AMT_ANNUITY`.
  This is a **proxy**, because it counts future installments (principal + interest) rather than
  principal alone. It must be labelled as a proxy everywhere it appears.

**Interview question.** *"Why not just use the sanctioned loan amount as exposure?"* Because it
ignores everything repaid so far; it overstates risk on seasoned accounts and makes old and new loans
incomparable.

---

### A3. DPD — Days Past Due

**What.** The number of days since the oldest **unpaid** amount fell due. It resets to zero only when
the account is fully current.

**Why it matters.** DPD is the single most important state variable in retail lending. Almost every
delinquency, provisioning and collections rule is written in terms of it.

**Worked example.** EMI due 5 Jan, unpaid. On 20 Jan the account is 15 DPD. Come 5 Feb, a second EMI
falls due and is also missed — the account is now 31 DPD (counted from the *oldest* unpaid due date,
5 Jan), not 15 again. **DPD counts from the oldest unpaid dues, not the most recent.**

**In our data.** `POS_CASH_balance.SK_DPD` and `credit_card_balance.SK_DPD` — DPD of that account in
that month. `SK_DPD_DEF` is the same measure but **ignoring small-value tolerance** (loans where a
trivial residual amount is not treated as delinquent). We must choose one, justify it, and use it
consistently. `bureau_balance.STATUS` encodes DPD in *bucket* form (0, 1, 2, 3, 4, 5) rather than days.

**Interview question.** *"An account misses January, pays February on time. What's the DPD in
February?"* Still delinquent — roughly 31+ days, because January's due amount is still outstanding. A
current payment does not cure an older miss.

---

### A4. Delinquency vs Default vs NPA

These three are constantly confused. They are not the same thing.

| Term | Meaning | Reversible? |
|---|---|---|
| **Delinquency** | A payment is late. Any DPD > 0. | Yes — pay up and the account cures |
| **Default** | A contractual/definitional threshold has been breached (commonly 90+ DPD) | Sometimes, but treated as a credit event |
| **NPA** (Non-Performing Asset) | The **regulatory** classification. Under RBI norms, a term loan becomes NPA when principal or interest is overdue for **more than 90 days** | Upgrade requires clearing the entire arrears |

**RBI's SMA framework** (Special Mention Accounts) — the early-warning ladder that sits *before* NPA:

| Classification | Overdue | Meaning |
|---|---|---|
| **SMA-0** | 1–30 days | Incipient stress |
| **SMA-1** | 31–60 days | Stress building |
| **SMA-2** | 61–90 days | Last stop before NPA |
| **NPA** | 90+ days | Non-performing |

Beyond NPA, assets are further graded **Substandard** (NPA up to 12 months), **Doubtful** (beyond
that), and **Loss**.

**Why this matters for you specifically.** This is core ICICI vocabulary and it is genuinely useful to
us: it means our delinquency buckets do not have to be invented. **[DECISION D2]** proposes adopting
these boundaries.

**Interview question.** *"Is a delinquent account a defaulted account?"* No. All defaults are
delinquent; most delinquencies never become defaults. Most 1–30 DPD accounts cure.

---

### A5. Delinquency buckets

**What.** Grouping accounts by DPD range so a portfolio can be described in a handful of states rather
than by individual day counts.

**Why it matters.** You cannot manage or report 300 distinct DPD values. Buckets make the portfolio
legible, and — critically — they are the states between which **roll rates** are measured.

**Proposed buckets** (mirroring RBI SMA/NPA boundaries):

| Bucket | DPD | RBI equivalent |
|---|---|---|
| Current | 0 | Standard |
| Bucket 1 | 1–30 | SMA-0 |
| Bucket 2 | 31–60 | SMA-1 |
| Bucket 3 | 61–90 | SMA-2 |
| Bucket 4 | 90+ | NPA-equivalent |

**In our data.** Derived from `SK_DPD` with a `CASE` expression. `bureau_balance.STATUS` already
arrives pre-bucketed on the same 30-day grid (`1`=1–30, `2`=31–60, …), which is a convenient
cross-check.

**Interview question.** *"Why 30-day buckets and not 15 or 45?"* Because dues are monthly, so a
30-day grid maps one bucket to one missed installment — and it matches the regulatory convention.

---

### A6. Roll rate

**What.** The probability that an account in bucket X this month is in bucket Y next month.
"Forward roll" = getting worse; "cure" = getting better.

**Why it matters.** It is the single best measure of *momentum*. Two portfolios can have identical
delinquency today and completely different futures. A book where 40% of Bucket-1 accounts roll forward
is in far more trouble than one where 8% do — even at the same headline delinquency rate.

**Worked example.** 1,000 accounts in Bucket 1 (1–30 DPD) in March. In April: 600 cured to Current,
250 stayed in Bucket 1, 150 rolled to Bucket 2.
→ Cure rate 60%, forward roll rate **15%**.
If the 30-60 roll is 15%, 60-90 is 50% and 90+ is 80%, then of 1,000 Bucket-1 accounts roughly
`1000 × 0.15 × 0.50 × 0.80 = 60` reach NPA. That chain is how lenders forecast future NPAs from
today's early-bucket population.

**In our data.** `LAG(bucket) OVER (PARTITION BY SK_ID_PREV ORDER BY MONTHS_BALANCE)` on
`POS_CASH_balance` / `credit_card_balance` / `bureau_balance`. **Watch for gaps** in the monthly
series — consecutive *rows* are not necessarily consecutive *months*, and assuming they are silently
corrupts the transition matrix.

**Interview question.** *"Delinquency is flat month over month. Is the book stable?"* Not necessarily
— flat totals can hide a rising forward-roll rate offset by new accounts entering. Check the
transitions, not just the level.

---

### A7. Vintage analysis and Months on Book (MOB)

**What.** **MOB** is the age of an account since origination. **Vintage analysis** groups accounts by
when they were originated (the cohort) and tracks performance *by age*, so cohorts are compared at
equal maturity.

**Why it matters.** Comparing a 3-month-old cohort's delinquency to a 3-year-old cohort's is
meaningless — loans need time to go bad. Vintage curves are how a lender detects that underwriting
quality has slipped: if the loans written recently are worse at MOB 6 than older ones were at MOB 6,
something changed in the credit policy.

**Worked example.**

| Cohort | MOB 3 | MOB 6 | MOB 9 | MOB 12 |
|---|---|---|---|---|
| Older cohort | 0.8% | 1.9% | 2.6% | 3.0% |
| Recent cohort | 1.6% | 3.7% | — | — |

The recent cohort is roughly double at equal age. That is an underwriting signal, visible long before
it shows up in the headline portfolio number.

**In our data.** MOB per contract = `MONTHS_BALANCE − MIN(MONTHS_BALANCE) OVER (PARTITION BY SK_ID_PREV)`.
Cohorts come from `previous_application.DAYS_DECISION` bucketed into origination-recency bands.
**Limitation:** cohorts are **relative-time bands** ("originated 0–12 months before the application"),
not calendar quarters, because the dataset contains no calendar dates.

**Interview question.** *"Why not just compare delinquency by origination month directly?"* Because
recent cohorts have had less time to deteriorate. You must compare at equal MOB or the young cohorts
always look better.

---

### A8. Credit utilisation

**What.** For revolving credit: balance ÷ credit limit.

**Why it matters.** Utilisation is a behavioural stress signal that appears *before* missed payments.
A customer running at 95% of limit month after month has no headroom left; one shock and they miss.

**Worked example.** Limit ₹1,00,000. Customer A carries ₹15,000 (15%); Customer B carries ₹97,000
(97%). Both are current. B is materially more fragile.

**In our data.** `credit_card_balance.AMT_BALANCE / AMT_CREDIT_LIMIT_ACTUAL`. Zero or NULL limits must
be excluded, not silently divided by.

**Interview question.** *"Both customers are current. Why treat one as higher risk?"* Because
utilisation measures capacity headroom, and headroom is what absorbs a shock. It is a leading
indicator; DPD is a lagging one.

---

### A9. Collections and prioritisation

**What.** Collections is the function that pursues repayment once an account is delinquent.
Prioritisation is deciding **who to contact first** with limited capacity.

**Why it matters.** A collections team might have capacity for a few thousand contacts a day against
a much larger delinquent population. Ordering that queue well is worth real money — and it is a
ranking problem, which is exactly what SQL is good at.

**Typical priority inputs.** Severity (DPD bucket) · exposure (money at risk) · momentum (deteriorating
vs curing) · history (chronic vs first-time misser).

**Critical honesty constraint.** Our data contains **no collections outcomes** — no contact records,
no promise-to-pay, no recovery amounts. So we can rank accounts by risk and exposure, but we **cannot**
claim any recovery rate, or that contacting these accounts cures them. The deliverable is a
*prioritisation framework*, not a proven intervention.

**Interview question.** *"Why not just call the highest-DPD accounts first?"* Because severity ignores
both exposure and curability. Very-high-DPD accounts are often the least likely to cure, while a
large, recently-slipped account may be both recoverable and expensive to lose.

---

## Part B — The business problem  **[DECISION D1]**

### The structural insight that shapes everything

In this dataset, `MONTHS_BALANCE = -1` means *one month before **that customer's** loan application*.
So every customer's behavioural history runs **up to the moment they applied for new credit**.

That is not an awkward artifact — it is a genuine and very recognisable business moment: **the state
of a customer's existing credit at the point they come back asking for more.** Every framing below is
anchored there.

### Candidate framings

**Framing A — Active book monitoring & collections triage**
Treat internal contracts still `Active` at their final observed month as the live book. Measure DPD
distribution, exposure concentration, roll rates and vintage curves; output a ranked collections queue.
*Strong operational story with a real decision artifact. Uses about 70% of the available data — the
`TARGET` outcome goes unused.*

**Framing B — Early-warning signals validated against observed outcome**
Build behavioural stress signals from history; test them against `application_train.TARGET`.
*Strongest evidence base — real, quotable numbers. But it is closer to credit scoring than collections,
and carries a real risk of sliding into an ML project, which you explicitly don't want.*

**Framing C — Both halves, joined by one idea** ← **recommended**
> A consumer lender needs to answer two questions from the same behavioural evidence:
> **(1) Of the accounts on our books right now, which are in repayment stress, how fast are they
> deteriorating, and which deserve our limited collections capacity first?**
> **(2) Do those same stress signals, observed at the point of a new application, identify borrowers
> who go on to have payment difficulty — and by how much?**

**Why C is the right answer.** It uses each half of the data for what it is actually good for. The
behavioural panels (POS, card, bureau, installments) describe the book; `TARGET` provides an
independent outcome to *validate the signals against*. The same analytical asset serves two decisions —
**who to collect from now**, and **who to watch at origination**. It requires no extra modules beyond
M1–M13 already scoped; it just binds them into one story instead of two disconnected halves.

Crucially, C is what makes the early-warning framework **evidence-based rather than asserted.** Most
student risk frameworks are a pile of plausible rules with nothing to test them on. Yours will have a
measured outcome rate behind every rule.

### Working title
**Loan Portfolio, Delinquency & Collections Intelligence System**

---

## Part C — Stakeholders

| Stakeholder | What they need to know | Why they need it | Decision it drives | Our module |
|---|---|---|---|---|
| **Collections Manager** | Which delinquent accounts, ranked; exposure at risk; who is deteriorating vs curing | Capacity is finite; the queue order determines what gets recovered | Who to contact today; which cases to escalate | M12 (priority queue), M5 |
| **Credit Risk Manager** | Roll rates between buckets; vintage curves; which behavioural signals precede difficulty | Needs to know where the book is heading, not just where it is | Tighten or loosen underwriting; forecast future NPA formation | M7, M8, M10, M11 |
| **Portfolio / Business Head** | Book size, product mix, exposure concentration, delinquency by segment | Owns growth-vs-quality trade-off | Where to grow, where to pull back | M1, M6 |
| **Credit Policy / Underwriting** | Which applicant-level signals are associated with later payment difficulty, and how strongly | Policy rules must be evidence-based and explainable | What becomes a decline rule vs a referral trigger | M10, M11 |
| **Data Analyst (you)** | Table grain, join cardinality, data-quality state | Every number above is only as good as the joins behind it | What can honestly be claimed, and what cannot | M2, M3 |

**Design rule that follows from this table:** every Power BI page in Phase 12 must map to a named
stakeholder and a named decision. If a visual serves nobody in this table, it gets cut.

---

## Part D — Scope

### In scope
- Portfolio composition & exposure of the behavioural book
- Repayment behaviour at installment grain (lateness, shortfall, consistency)
- DPD measurement and bucketing on the RBI SMA/NPA grid **[D2]**
- Delinquency concentration by borrower and product segment
- Roll-rate transition matrices
- Vintage / MOB deterioration curves by origination-recency cohort
- A transparent, rule-based early-warning framework
- Validation of that framework against `application_train.TARGET`
- A ranked collections prioritisation queue
- A four-page Power BI decision layer
- Full data-quality, assumption and limitation registers

### Explicitly out of scope
| Excluded | Reason |
|---|---|
| Any geographic analysis | No state/city in the data — only `REGION_RATING_CLIENT` 1–3 |
| Calendar-time trends or calendar vintages | No calendar dates anywhere in the dataset |
| Collections effectiveness / recovery rates | No collections outcome data exists |
| Loss Given Default, provisioning amounts | No recovery or collateral data |
| Machine-learning default prediction | Deliberate. Early warning stays rule-based and explainable |
| Any claim the data represents India | Country is not disclosed by the publisher |

---

## Part E — Open decisions

**[D1]** Business problem framing → **recommend C**
**[D2]** Delinquency bucket boundaries → **recommend the RBI SMA/NPA grid** (0 / 1–30 / 31–60 /
61–90 / 90+). Same boundaries a generic scheme would use, but with a real, citable industry
justification instead of an arbitrary one — and directly relevant to an ICICI interview. We state
clearly that we adopt the convention because it is a recognised standard, **not** because the data is
Indian.
**[D3]** Deferred to Phase 5: `SK_DPD` vs `SK_DPD_DEF` as the DPD measure. Needs the data inspected
first — we will decide it on evidence, not preference.
