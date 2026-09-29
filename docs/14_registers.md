# Project Registers

Assumption · Insight · Learning. (The limitation register lives in
[13_executive_summary.md](13_executive_summary.md) §7.)

---

## 1. Assumption register

| # | Assumption | Why needed | Risk if wrong | Alternative considered |
|---|---|---|---|---|
| A1 | **POS exposure ≈ `CNT_INSTALMENT_FUTURE × AMT_ANNUITY`** | No outstanding-balance field exists for POS/cash loans, and 85% of book exposure is POS | Overstates exposure — annuity includes interest, not principal alone. Affects the entire top of the collections queue | Use CARD only (rejected: only 47 accounts in the 31–90 bucket); omit POS exposure (rejected: removes 85% of the book) |
| A2 | **The "book" is each account at its latest observed month** | No calendar dates, so no common as-of date exists | Accounts are observed at different real-world moments; the snapshot is relative-time | Fix a common `MONTHS_BALANCE` (rejected: throws away accounts not alive at that index) |
| A3 | **`SK_DPD` is the primary delinquency measure** (`SK_DPD_DEF` as materiality filter) | Two DPD fields exist and disagree on 61% of POS delinquent months | If tolerance-adjusted DPD is the "true" operational measure, delinquency is overstated ~2.5× | `SK_DPD_DEF` primary — rejected on evidence: it empties the 31–90 bucket (12,940 → 1,152), making roll rates impossible |
| A4 | **Lateness measured at first payment (risk) and full settlement (exposure)** | An installment can be settled by several payments 36.7 days apart | Using only settlement understates the risk signal (1.33× vs 1.88× lift) | Single definition — rejected: the two measure genuinely different things |
| A5 | **Delinquency buckets: 0 / 1–30 / 31–60 / 61–90 / 91–360 / 360+** | Needed a defensible ladder; RBI SMA/NPA boundaries provide the convention | The 360 split is ours, not a standard | Plain RBI grid — rejected: 360+ holds more accounts (3,022) than 91–360 (2,330) and means something operationally different |
| A6 | **31–90 merged for roll-rate analysis** | Only 542 accounts ever peak at 61–90 | Loses the SMA-1/SMA-2 distinction in momentum analysis | Keep split — rejected: transition cells too thin to be stable |
| A7 | **`DAYS_EMPLOYED = 365243` means "not employed"** | 18.01% of rows carry it | If it meant something else, a whole segment is mislabelled | Verified: 99.98% of Pensioners, 100% of Unemployed, 0% of everyone else |
| A8 | **NULL `DAYS_*` in `previous_application` are structural** | 40.30% null across five columns | If random, vintage cohorts are biased | Verified: 100% null for Canceled/Refused/Unused; a contract never disbursed has no schedule |
| A9 | **Cure rates transfer from the panel to the current queue** | Needed a curability weight per bucket | Historical transition rates may not hold for today's accounts | Stated as an observed historical rate, never as a prediction |
| A10 | **`bureau_balance` is duplicative of the internal panels** | Justified dropping 27.3M rows (47% of the DB) | Loses external monthly roll rates | Kept `bureau` (1.7M) so external signals survive — and S3 proved the strongest single signal (1.97×) |
| A11 | **`application_test` belongs in the model** with a `SOURCE` flag | 14% of child rows otherwise appear orphaned | None material — test rows are excluded from all outcome analysis | Verified: reduced apparent orphan rate to exactly 0 |

---

## 2. Insight register

Confidence: **High** = reproduced by ≥2 independent paths, large n · **Medium** = single path, adequate n · **Low** = small n or confounded.

| ID | Business question | Finding | Evidence | Confidence | Recommendation |
|---|---|---|---|---|---|
| I1 | Should collections rank by severity? | **No — it is close to the worst possible key.** Top 10% by DPD reaches 0.0% of curable value; by value, 79.8% | Phase 10 C4; 7,211 accounts | **High** | R1 |
| I2 | Where is the money in the delinquent book? | 91.2% of curable value is in the *mildest* bucket (1–30). The 360+ bucket holds 0.0% | Phase 7 R4, Phase 10 C2 | **High** | R1, R2 |
| I3 | When does curing stop? | At day 90. Cure falls 55–59% → 23–32% → 4.3–6.8%; 91+ buckets are absorbing (85–98% stay) | Phase 8 V4; 12.5M transitions | **High** | R3 |
| I4 | Does utilisation precede delinquency? | Ever-delinquent rises monotonically 1.3% → 35.8% across utilisation bands — a 27× spread | Phase 7 R5; 90,952 active cards | **High** | R4 |
| I5 | Do demographics explain current delinquency? | **No.** Flat at 2.03%–2.36% across all income types and age bands | Phase 6 P4; 327,101 accounts | **High** | R5 |
| I6 | Do demographics predict new-loan default? | **Yes** — 4.5%–11.2% by age. Opposite conclusion, different outcome | Phase 9 E5; 307,511 customers | **High** | R7 |
| I7 | Is card delinquency material? | Only 23% survives the tolerance test, vs 60% for POS | Phase 6 P3 | **High** | R6 |
| I8 | Does repayment history predict default? | Monotonic: 5.98% (no history) → 14.25% (late >30% of installments) | Phase 7 R1; 307,511 customers | **High** | R7 |
| I9 | Does the *count* of late events matter? | Mostly no. 0→1 adds +80%; 1→7+ adds only +16% | Phase 7 R2 | **High** | Prefer a binary rule over a count |
| I10 | Do behavioural signals stack? | Yes: 1 signal ≈1.8×, 2 ≈2.6–2.8×, 3 = 7.4% — but n=5 on the last | Phase 7 R8 | **Medium** | R7 |
| I11 | Is "credit hunger" a risk signal here? | **No.** 2+ bureau enquiries in a quarter = 1.04× lift — no signal | Phase 9 E1; 16,713 customers | **High** | Negative result; do not use |
| I12 | Is missing external data informative? | Yes. Missing `EXT_SOURCE_3` → 9.31% vs 7.77% present (20% relative) | Phase 5 DQ-15 | **High** | Never mean-fill; use a missing flag |
| I13 | How strong is the early-warning framework? | **Modest.** 1.27× at 16% coverage; 1.80× at 1.0%. Scores 1 and 2 indistinguishable | Phase 9 E3/E4 | **High** | R7 — supplement, not gate |
| I14 | Did underwriting quality improve? | **Unproven.** 6.5× gradient at equal age, but product-mix, selection and censoring confounds cannot be separated | Phase 8 V6 | **Low** | R8 — investigate, do not conclude |
| I15 | Is the live book representative of lifetime risk? | No. 9.39% of accounts were ever delinquent; 2.20% are now — accounts that fail get closed | Phase 6 P3 | **High** | Never quote book delinquency as lifetime risk |
| I16 | Does deterioration predict trouble on *other* credit? | Yes — 11.996% vs 7.627% `TARGET`, a 1.57× lift on a different loan | Phase 7 R6 | **Medium** | Feeds P1 tier definition |
| I17 | What is the true grain of the payment table? | One row = one **payment event**, not one installment. 653,483 split payments; max 12 payments for one installment | Phase 2 F1; three independent paths | **High** | Aggregate before comparing — else 1,295,493 rows falsely read as short |

---

## 3. Learning log

| Concept | Understood? | Used where | Interview-ready? |
|---|---|---|---|
| Table grain | ✅ | Phase 2 — discovered `installments_payments` is payment-event grain, not installment | **Yes** — best story in the project |
| Join cardinality / fan-out | ✅ | Phase 2, Phase 11 OPT-4 — measured 37.5× inflation | **Yes** — with a measured number |
| Referential integrity / orphans | ✅ | Phase 2 F2/F3 — distinguished artefact orphans from real ones | Yes |
| Primary/foreign keys, star schema | ✅ | Phase 3 schema, Phase 12 Power BI model | Yes |
| Sentinel values & encodings | ✅ | Phase 5 — decoded `365243` to "not employed" | Yes |
| Structural vs random NULLs | ✅ | Phase 5 DQ-06 — 40.30% nulls proven structural | Yes |
| `LEFT JOIN` vs `INNER JOIN` | ✅ | Throughout — orphan preservation | Yes |
| `GROUP BY` / `HAVING` | ✅ | Suppressing thin segments | Yes |
| Conditional aggregation (`SUM(cond)`) | ✅ | Every signal and rate calculation | Yes |
| CTEs | ✅ | Roll rate, cure rate, threshold analysis | Yes |
| `LAG` / window functions | ✅ | Phase 8 roll rates, Phase 7 deterioration | Yes |
| `ROW_NUMBER` / `NTILE` | ✅ | Book snapshot, exposure deciles, value quintiles | Yes |
| Window frames & partitioning | ✅ | `SUM() OVER (PARTITION BY ...)` for shares | Yes |
| Index design & covering indexes | ✅ | Phase 11 OPT-3 — 18× via covering index | Yes |
| Execution plans (`EXPLAIN`) | ✅ | Phase 11 — diagnosed a *failed* optimisation | **Yes** — the failure is the story |
| Materialisation vs re-computation | ✅ | Phase 6 mart — 275.7s → 0.09s | Yes |
| Bulk loading (`LOAD DATA LOCAL INFILE`) | ✅ | Phase 4 — 58.4M rows in 15.6 min | Yes |
| Reconciliation & independent validation | ✅ | Phase 11 — three paths, 20 checks | **Yes** |
| DPD | ✅ | Throughout | Yes |
| Delinquency vs default vs NPA | ✅ | Phase 1 concepts, Phase 6 metrics | Yes |
| RBI SMA framework | ✅ | Bucket design | Yes |
| Roll rate & absorbing states | ✅ | Phase 8 — found the 90-day cliff | **Yes** |
| Cure rate | ✅ | Phase 8, Phase 10 ranking input | Yes |
| Vintage / months-on-book | ✅ | Phase 8 — plus the MOB-validity check | Yes |
| Exposure vs loan amount | ✅ | Phase 6/7 — and its proxy limitation | Yes |
| Credit utilisation as a leading indicator | ✅ | Phase 7 R5 — 27× spread | Yes |
| Lift, precision, recall, base rate | ✅ | Phase 9 — full threshold analysis | Yes |
| Survivorship bias | ✅ | Phase 6 — 9.39% ever vs 2.20% now | Yes |
| Correlation vs causation | ✅ | Every recommendation's language | Yes |
| Confounding | ✅ | Phase 8 V6 — declined to conclude | **Yes** |
| Small-n discipline | ✅ | n=67, n=22, n=5 all published with counts | Yes |
