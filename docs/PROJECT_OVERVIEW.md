# Project Overview
## Loan Portfolio, Delinquency & Collections Intelligence System

*A two-page explanation of what this project solves, why it matters, and how it was built.*

---

## 1. The problem

A consumer lender has thousands of customers who are behind on payments and a
collections team that can only contact a fraction of them each day. **Which ones
do you call first?**

The instinctive answer is "the worst ones" — the accounts furthest past due. That
is how most collections queues are ordered, and this project shows it is close to
the worst possible choice.

There is a second question underneath it. When a customer who already holds
credit applies for *more* credit, their existing repayment behaviour is sitting
right there in the data. **Does that behaviour tell you anything about whether
the new loan will go bad?**

Both questions had plausible-sounding answers that nobody had actually measured.

---

## 2. Why it matters

Collections capacity is finite and expensive. Every hour spent on an account that
will never pay is an hour not spent on one that might. Getting the queue order
wrong doesn't just waste effort — it quietly loses recoverable money, and because
nobody sees the counterfactual, it looks like the team is working hard.

For a lender, this sits at the junction of three functions:

| Function | What they need from this |
|---|---|
| **Collections** | A ranked list of who to work today |
| **Credit Risk** | How fast accounts deteriorate, and which behaviours precede trouble |
| **Portfolio / Business** | Where the book's stress is concentrated |

---

## 3. The data

**Home Credit Default Risk** — a real, anonymised consumer-lending dataset
published by Home Credit Group.

- **58.4 million rows** across **7 related tables**
- **356,255 borrowers**, **1,040,632 credit accounts**
- Monthly behavioural history: account balances, days-past-due, credit limits
- Installment-level records: what was due, what was actually paid, and when
- External credit-bureau records for each borrower
- A recorded outcome — whether each borrower had payment difficulty on a new loan

> **On the data's origin.** Real India-specific lending data was searched for
> first, across 14 source families in three separate rounds. It exists — but it is
> not public, for statutory and privacy reasons (India has no public loan-level
> release; borrower-level data reaches researchers only under NDA). This dataset's
> country is not disclosed by its publisher, and **no claim is made that it
> represents India or any named market.**

---

## 4. What was built

Twelve phases, each gated on evidence before moving to the next.

```
business problem → data inspection → schema design → load 58.4M rows to MySQL
    → data-quality assessment → portfolio baseline → repayment behaviour
    → delinquency & roll-rate → vintage analysis → early-warning framework
    → collections prioritisation → validation → Power BI decision layer
```

**Tools:** MySQL 8.0 (the analytical engine — ~2,600 lines of SQL across 17 files),
Python/pandas (independent validation only), Power BI (the decision layer).

The centrepiece is a **collections priority queue**: 7,211 delinquent accounts,
ranked not by how late they are but by **money at risk × the observed probability
that accounts in that state recover**. Both inputs were measured from the data,
not assumed.

---

## 5. What was found

**The "worst" accounts have no money in them.** Accounts more than 360 days past
due are 19% of the delinquent book by headcount — and hold a **mean balance of
₹179**. Accounts only 1–30 days late hold **₹465.7 million**. Mean exposure
actually *peaks* at 61–90 days and then collapses.

**Ranking by severity reaches nothing.** Working the top 10% of the queue sorted
by days-past-due reaches **0.0%** of recoverable value. Sorted by money-at-risk ×
recovery-likelihood, the same 10% reaches **79.8%**.

**Recovery effectively stops at 90 days.** Accounts 1–30 days late recover on
their own **55–59%** of the time. Past 90 days, that falls to **4–7%**, and
85–98% simply stay where they are.

**Credit utilisation warns before payments are missed.** Cards that have run over
their limit are **27× more likely** to have been delinquent than cards kept below
30% utilisation — and utilisation is visible *before* a payment is missed.

**Demographics don't explain who is behind.** Delinquency is flat at 2.03–2.36%
across every income type and age band. Prioritisation has to be built on
behaviour and exposure, not on who the borrower is.

**And one finding that was deliberately not acted on.** Older loan cohorts show
6.5× the delinquency of recent ones at the same age. That is consistent with
improving underwriting — but product mix, customer selection and observation
censoring cannot be separated with this data. It is reported as a flag for
investigation, not as a conclusion.

---

## 6. How the numbers are trusted

Every headline figure was derived **three independent ways** — the analytical
pipeline, a separate SQL path querying the raw tables, and Python/pandas reading
the original CSV files. Different engines, different code, same source.

**20 reconciliation checks. All exact.**

---

## 7. What this project does not claim

- **Not a recovery forecast.** Recovery rates are observed natural month-to-month
  transitions. The dataset contains no contact records, promises to pay, or
  amounts recovered, so no claim is made that calling an account causes it to pay.
- **No causation.** Every relationship is stated as association.
- **Exposure for one product is estimated,** not measured — about 85% of book
  exposure is a derived figure, and the top of the priority queue rests entirely
  on it. This is stated in the summary, not buried in an appendix.
- **No geography and no calendar trends** — the data contains neither.
