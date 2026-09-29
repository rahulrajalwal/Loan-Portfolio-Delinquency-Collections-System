-- ############################################################################
--  LOAN PORTFOLIO, DELINQUENCY & COLLECTIONS INTELLIGENCE
--  KEY QUERIES - one file, in story order
--
--  HOW TO USE THIS FILE
--  --------------------
--  1. Open in MySQL Workbench (File > Open SQL Script)
--  2. Click inside ONE query, press Ctrl+Enter  -> runs just that query
--     Do NOT press Ctrl+Shift+Enter (it runs all 20 and opens 20 result tabs)
--  3. Read the comment above each query first - it says what to look for
--
--  100% READ-ONLY. Nothing here creates, drops or changes anything.
--  Safe to run any query, any number of times, in any order.
--
--  PART A - the headline results. All fast (under ~5 seconds each).
--  PART B - the evidence underneath. Slower (30s - 4 min each).
--
--  Base rate to keep in mind throughout: TARGET = 8.0729%
-- ############################################################################

USE loan_portfolio;


-- ############################################################################
--  PART A - THE HEADLINE RESULTS          (run these first - all fast)
-- ############################################################################

-- ============================================================================
-- A0. Is the database loaded?
-- EXPECT: 1,040,632 accounts / 356,255 customers / 7,211 in the queue
-- ============================================================================
SELECT 'accounts (the book)'    AS object_name, COUNT(*) AS rows_present FROM mart_account
UNION ALL SELECT 'customers',                   COUNT(*) FROM mart_customer
UNION ALL SELECT 'collections queue',           COUNT(*) FROM mart_queue_tiered
UNION ALL SELECT 'roll-rate cells',             COUNT(*) FROM mart_roll_rate;


-- ============================================================================
-- A1. THE BOOK - how big is it and what is it made of?
-- EXPECT: 327,101 active of 1,040,632. POS only 25% active, CARD 87%.
-- WHY: POS loans are ~10-month consumer-durable loans that COMPLETE and close.
--      Cards revolve and stay open. Two different product lifecycles.
-- ============================================================================
SELECT PRODUCT,
       COUNT(*)                                                      AS accounts,
       SUM(IS_ACTIVE)                                                AS active,
       ROUND(100.0*SUM(IS_ACTIVE)/COUNT(*), 2)                       AS pct_active,
       ROUND(SUM(CASE WHEN IS_ACTIVE=1 THEN EXPOSURE END)/1000000,1) AS exposure_m,
       SUM(IS_ACTIVE=1 AND DPD_NOW>0)                                AS delinquent,
       ROUND(100.0*SUM(IS_ACTIVE=1 AND DPD_NOW>0)/SUM(IS_ACTIVE),3)  AS delinq_rate_pct
FROM mart_account
GROUP BY PRODUCT WITH ROLLUP;


-- ============================================================================
-- A2. EXPOSURE CONCENTRATION - is the money spread evenly?
-- EXPECT: decile 1 holds ~51.5% of all exposure. Deciles 1+2 = ~72%.
-- WHY IT MATTERS: this is the argument for exposure-weighting everything.
-- SQL note: NTILE(10) is a window function - it splits rows into 10 equal
--           groups after ordering by exposure descending.
-- ============================================================================
SELECT decile,
       COUNT(*)                                                 AS accounts,
       ROUND(SUM(EXPOSURE)/1000000, 1)                          AS exposure_m,
       ROUND(100.0*SUM(EXPOSURE)/SUM(SUM(EXPOSURE)) OVER (), 2) AS pct_of_exposure
FROM (SELECT EXPOSURE, NTILE(10) OVER (ORDER BY EXPOSURE DESC) AS decile
      FROM mart_account WHERE IS_ACTIVE=1 AND EXPOSURE > 0) t
GROUP BY decile ORDER BY decile;


-- ============================================================================
-- A3. *** THE CORE FINDING *** why severity is the wrong sort key
-- EXPECT: 1-30 holds 5,163 accounts and 465M. 360+ holds 1,369 accounts
--         and 0.2M - a MEAN BALANCE OF 179.
-- READ IT AS: the "worst" accounts have no money and never cure.
-- ============================================================================
SELECT BUCKET_ANALYTICAL                                AS bucket,
       COUNT(*)                                         AS accounts,
       ROUND(SUM(EXPOSURE)/1000000, 2)                  AS exposure_m,
       ROUND(AVG(EXPOSURE), 0)                          AS mean_exposure,
       ROUND(AVG(cure_rate)*100, 2)                     AS observed_cure_pct,
       ROUND(SUM(cure_weighted_exposure)/1000000, 2)    AS curable_value_m,
       ROUND(100.0*SUM(cure_weighted_exposure)
             /SUM(SUM(cure_weighted_exposure)) OVER (), 2) AS pct_curable_value
FROM mart_collections_queue
GROUP BY BUCKET_ANALYTICAL
ORDER BY FIELD(BUCKET_ANALYTICAL,'1-30','31-90','91-360','360+');


-- ============================================================================
-- A4. *** THE PROOF *** ranking by value vs ranking by DPD
-- EXPECT: at 10% of capacity - VALUE sort reaches 79.82%, DPD sort reaches 0.00%
-- THIS IS THE PROJECT'S HEADLINE. Same 7,211 accounts, two sort orders.
-- SQL note: two ROW_NUMBER() windows over the same rows, one per sort key.
-- ============================================================================
WITH ranked AS (
    SELECT cure_weighted_exposure AS v,
           ROW_NUMBER() OVER (ORDER BY cure_weighted_exposure DESC) AS rn_value,
           ROW_NUMBER() OVER (ORDER BY DPD_NOW DESC)                AS rn_dpd,
           COUNT(*)                    OVER () AS n,
           SUM(cure_weighted_exposure) OVER () AS total_value
    FROM mart_collections_queue
)
SELECT pct_worked AS pct_of_capacity_worked,
       ROUND(100.0*SUM(CASE WHEN rn_value <= n*pct_worked/100 THEN v ELSE 0 END)
             /MAX(total_value), 2) AS pct_value_reached_BY_VALUE,
       ROUND(100.0*SUM(CASE WHEN rn_dpd   <= n*pct_worked/100 THEN v ELSE 0 END)
             /MAX(total_value), 2) AS pct_value_reached_BY_DPD
FROM ranked
CROSS JOIN (SELECT 5 AS pct_worked UNION SELECT 10 UNION SELECT 20
            UNION SELECT 30 UNION SELECT 50) p
GROUP BY pct_worked ORDER BY pct_worked;


-- ============================================================================
-- A5. THE 90-DAY CLIFF - roll rates
-- EXPECT: 1-30 cures 55-59%. 31-90 cures 23-32%. 91-360 cures only 4-7%.
-- READ IT AS: past 90 days accounts are absorbing - they don't come back.
-- SQL note: FIELD() gives the buckets an order so we can call a move "cure"
--           (to a lower bucket) or "forward roll" (to a higher one).
-- ============================================================================
SELECT PRODUCT, from_bucket,
       SUM(transitions)                                              AS observed_transitions,
       ROUND(100.0*SUM(CASE WHEN t_ord < f_ord THEN transitions END)/SUM(transitions),2) AS cure_pct,
       ROUND(100.0*SUM(CASE WHEN t_ord = f_ord THEN transitions END)/SUM(transitions),2) AS stay_pct,
       ROUND(100.0*SUM(CASE WHEN t_ord > f_ord THEN transitions END)/SUM(transitions),2) AS forward_roll_pct
FROM (SELECT PRODUCT, from_bucket, to_bucket, transitions,
             FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+') AS f_ord,
             FIELD(to_bucket,  '0-current','1-30','31-90','91-360','360+') AS t_ord
      FROM mart_roll_rate) x
GROUP BY PRODUCT, from_bucket
ORDER BY PRODUCT, FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+');


-- ============================================================================
-- A6. THE FULL ROLL-RATE MATRIX (for the Power BI heatmap)
-- EXPECT: 40 rows. Note how the diagonal dominates past 90 days.
-- ============================================================================
SELECT PRODUCT, from_bucket, to_bucket, transitions,
       SUM(transitions) OVER (PARTITION BY PRODUCT, from_bucket) AS from_total,
       ROUND(100.0*transitions
             / SUM(transitions) OVER (PARTITION BY PRODUCT, from_bucket), 2) AS roll_pct
FROM mart_roll_rate
ORDER BY PRODUCT,
         FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+'),
         FIELD(to_bucket,  '0-current','1-30','31-90','91-360','360+');


-- ============================================================================
-- A7. THE COLLECTIONS QUEUE - priority tiers
-- EXPECT: P1+P2 = ~20% of the queue holding ~96% of curable value.
--         P5 (360+) = 19% of accounts, 0.0% of value - not a collections case.
-- ============================================================================
SELECT priority_tier,
       COUNT(*)                                                     AS accounts,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 2)                AS pct_of_queue,
       ROUND(SUM(EXPOSURE)/1000000, 2)                               AS exposure_m,
       ROUND(SUM(cure_weighted_exposure)/1000000, 2)                 AS curable_value_m,
       ROUND(100.0*SUM(cure_weighted_exposure)
             /SUM(SUM(cure_weighted_exposure)) OVER (), 2)           AS pct_curable_value,
       ROUND(AVG(DPD_NOW), 0)                                        AS avg_dpd
FROM mart_queue_tiered
GROUP BY priority_tier ORDER BY priority_tier;


-- ============================================================================
-- A8. THE ACTUAL DELIVERABLE - top 25 accounts to work
-- This is the list you hand to a collections team.
-- ============================================================================
SELECT SK_ID_PREV                      AS account_id,
       PRODUCT, BUCKET_ANALYTICAL      AS bucket,
       DPD_NOW                         AS dpd,
       ROUND(EXPOSURE, 0)              AS exposure,
       ROUND(cure_rate*100, 1)         AS cure_pct,
       ROUND(cure_weighted_exposure,0) AS curable_value,
       IS_DETERIORATING, IS_MATERIAL, IS_CHRONIC,
       priority_tier
FROM mart_queue_tiered
ORDER BY cure_weighted_exposure DESC
LIMIT 25;


-- ============================================================================
-- A9. UTILISATION LEADS DELINQUENCY (cards)
-- EXPECT: ever-delinquent rises 1.3% -> 35.8%. A 27x spread, monotonic.
-- READ IT AS: utilisation is a LEADING indicator; DPD is LAGGING.
-- ============================================================================
SELECT CASE WHEN MAX_UTILISATION IS NULL THEN '0: no limit recorded'
            WHEN MAX_UTILISATION <= 0.30 THEN '1: 0-30%'
            WHEN MAX_UTILISATION <= 0.60 THEN '2: 30-60%'
            WHEN MAX_UTILISATION <= 0.90 THEN '3: 60-90%'
            WHEN MAX_UTILISATION <= 1.00 THEN '4: 90-100%'
            ELSE '5: over limit' END                        AS utilisation_band,
       COUNT(*)                                             AS accounts,
       SUM(DPD_NOW > 0)                                     AS delinquent_now,
       ROUND(100.0*SUM(MAX_DPD_EVER > 0)/COUNT(*), 2)       AS ever_delinquent_pct
FROM mart_account
WHERE PRODUCT='CARD' AND IS_ACTIVE=1
GROUP BY utilisation_band ORDER BY utilisation_band;


-- ============================================================================
-- A10. DEMOGRAPHICS DO NOT EXPLAIN CURRENT DELINQUENCY
-- EXPECT: every segment between ~2.03% and ~2.36%. Essentially FLAT.
-- BUT compare with A12 - the same attributes DO predict new-loan default.
-- ============================================================================
SELECT c.NAME_INCOME_TYPE                                  AS income_type,
       COUNT(*)                                            AS active_accounts,
       COUNT(DISTINCT a.SK_ID_CURR)                        AS customers,
       ROUND(100.0*SUM(a.DPD_NOW > 0)/COUNT(*), 3)         AS delinquency_rate_pct
FROM mart_account a
JOIN mart_customer c ON c.SK_ID_CURR = a.SK_ID_CURR
WHERE a.IS_ACTIVE = 1
GROUP BY c.NAME_INCOME_TYPE
HAVING customers >= 1000
ORDER BY active_accounts DESC;


-- ============================================================================
-- A11. EARLY-WARNING SIGNALS - lift vs recall
-- EXPECT: sharp signals (lift ~1.9x) fire on only ~1% of the book.
--         Broad signals (recall 26-60%) have almost no lift.
--         S8 "credit hunger" = 1.04x - a NEGATIVE RESULT worth reporting.
-- ============================================================================
SELECT signal_code, signal_label, flagged, defaults,
       target_pct, lift, recall_pct
FROM pbi_signal
ORDER BY lift DESC;


-- ============================================================================
-- A12. THE FRAMEWORK vs THE OUTCOME
-- EXPECT: monotonic 0 -> 3 signals, BUT scores 1 and 2 are nearly identical
--         (~10.02% vs ~10.03%) - a real flaw, reported not hidden.
-- ============================================================================
SELECT signal_count,
       COUNT(*)                                       AS customers,
       SUM(TARGET)                                    AS defaults,
       ROUND(100.0*AVG(TARGET), 3)                    AS target_pct,
       ROUND(AVG(TARGET)/0.080729, 2)                 AS lift_vs_base
FROM (SELECT TARGET,
             (COALESCE(N_LATE_FIRST_30PLUS,0) > 0) + (COALESCE(N_SHORTFALL,0) > 0)
           + (COALESCE(N_BUREAU_OVERDUE,0) > 0) + (COALESCE(N_DETERIORATING_ACCOUNTS,0) > 0)
           + (COALESCE(MONTHS_DELINQUENT,0) >= 3)     AS signal_count
      FROM mart_customer WHERE SOURCE='train') t
GROUP BY signal_count ORDER BY signal_count;


-- ============================================================================
-- A13. SANITY CHECK - do the priority tiers contain riskier borrowers?
-- EXPECT: monotonic. P1 ~25.8% (3.20x base) down to P5 ~8.6% (1.07x).
-- NOTE: the tiering never looked at TARGET. This is an independent check.
-- ============================================================================
SELECT priority_tier,
       COUNT(TARGET)                    AS train_customers,
       ROUND(100.0*AVG(TARGET), 3)      AS target_pct,
       ROUND(AVG(TARGET)/0.080729, 2)   AS lift_vs_base
FROM mart_queue_tiered
WHERE TARGET IS NOT NULL
GROUP BY priority_tier ORDER BY priority_tier;


-- ============================================================================
-- A14. VINTAGE CURVES - cohorts compared at EQUAL age
-- EXPECT: at MOB 6, delinquency falls 4.11% (oldest cohort) -> 0.63% (newest).
-- CAUTION: do NOT conclude "underwriting improved". Product mix, selection
--          and censoring are all confounded. This is a flag, not a finding.
-- ============================================================================
SELECT cohort,
       MAX(CASE WHEN MOB=6  THEN accounts END)   AS accounts_at_mob6,
       MAX(CASE WHEN MOB=6  THEN dq END)         AS delinq_pct_mob6,
       MAX(CASE WHEN MOB=12 THEN dq END)         AS delinq_pct_mob12,
       MAX(CASE WHEN MOB=18 THEN dq END)         AS delinq_pct_mob18
FROM (SELECT cohort, MOB, SUM(accounts) AS accounts,
             ROUND(100.0*SUM(delinquent)/SUM(account_months), 3) AS dq
      FROM mart_vintage GROUP BY cohort, MOB) t
WHERE MOB IN (6,12,18)
GROUP BY cohort ORDER BY cohort;



-- ############################################################################
--  PART B - THE EVIDENCE UNDERNEATH      (slower: 30 s to ~4 min each)
--  Run these when you want to see WHERE the Part A numbers come from.
-- ############################################################################

-- ============================================================================
-- B1. *** THE FAN-OUT LESSON *** the same question asked two ways
-- EXPECT: correct = 209.40 billion. Fanned out = 7,843.74 billion.
--         That is 37.5x too large - and 140x slower.
-- WHY: joining customers to 12.9M installment rows repeats AMT_CREDIT once
--      per payment event. The multiplier VARIES per customer, so you cannot
--      even divide it out.
-- RUNTIME: ~90 seconds for the wrong one. That slowness is part of the lesson.
-- ============================================================================
SELECT 'CORRECT (customer grain)' AS method,
       ROUND(SUM(AMT_CREDIT)/1000000000, 2) AS total_credit_billions,
       COUNT(*)                             AS rows_aggregated
FROM mart_customer
UNION ALL
SELECT 'WRONG (fanned out via installments)',
       ROUND(SUM(c.AMT_CREDIT)/1000000000, 2),
       COUNT(*)
FROM mart_customer c
JOIN stg_installment i ON i.SK_ID_CURR = c.SK_ID_CURR;


-- ============================================================================
-- B2. *** THE GRAIN DISCOVERY *** one row is a PAYMENT, not an installment
-- EXPECT: 12,951,918 installments, 640,905 settled by 2+ payments,
--         max 12 payments for a single installment, 99.94% fully settled.
-- WHY IT MATTERS: comparing AMT_PAYMENT row-by-row would flag 1.3M rows as
--                 underpaid when they were paid in full.
-- RUNTIME: ~2 minutes
-- ============================================================================
SELECT COUNT(*)                                                AS installments,
       SUM(N_PAYMENTS > 1)                                     AS settled_by_multiple_payments,
       MAX(N_PAYMENTS)                                         AS max_payments_one_installment,
       ROUND(100.0*SUM(N_PAYMENTS > 1)/COUNT(*), 3)            AS pct_split,
       SUM(N_PAYMENTS > 1 AND ABS(SHORTFALL) < 0.01)           AS split_and_fully_settled
FROM stg_installment;


-- ============================================================================
-- B3. REPAYMENT BEHAVIOUR vs THE OUTCOME
-- EXPECT: monotonic. Never late 7.28% -> late >30% of installments 14.25%.
--         And "no installment history" is LOWEST at 5.98% (counterintuitive).
-- RUNTIME: ~5 seconds (uses the mart, not the panel)
-- ============================================================================
SELECT CASE WHEN PCT_LATE_FIRST IS NULL THEN '6: no installment history'
            WHEN PCT_LATE_FIRST =  0    THEN '1: never late'
            WHEN PCT_LATE_FIRST <=  5   THEN '2: late <=5%'
            WHEN PCT_LATE_FIRST <= 15   THEN '3: late 5-15%'
            WHEN PCT_LATE_FIRST <= 30   THEN '4: late 15-30%'
            ELSE '5: late >30%' END              AS repayment_band,
       COUNT(*)                                  AS customers,
       SUM(TARGET)                               AS defaults,
       ROUND(100.0*AVG(TARGET), 3)               AS target_pct,
       ROUND(AVG(TARGET)/0.080729, 2)            AS lift_vs_base
FROM mart_customer WHERE SOURCE='train'
GROUP BY repayment_band ORDER BY repayment_band;


-- ============================================================================
-- B4. SURVIVORSHIP - the live book looks healthier than lifetime experience
-- EXPECT: 9.39% of accounts were EVER delinquent; only 2.20% are delinquent NOW.
-- WHY: accounts that deteriorate badly get closed and leave the Active set.
-- ============================================================================
SELECT 'ever delinquent (full history)' AS lens,
       COUNT(*)                                                          AS accounts,
       SUM(MAX_DPD_EVER > 0)                                             AS n,
       ROUND(100.0*SUM(MAX_DPD_EVER > 0)/COUNT(*), 2)                    AS pct
FROM mart_account
UNION ALL
SELECT 'delinquent right now (live book)',
       SUM(IS_ACTIVE), SUM(IS_ACTIVE=1 AND DPD_NOW>0),
       ROUND(100.0*SUM(IS_ACTIVE=1 AND DPD_NOW>0)/SUM(IS_ACTIVE), 2)
FROM mart_account;


-- ============================================================================
-- B5. RECONCILIATION - the book rebuilt from the RAW tables
-- EXPECT: 1,040,632 / 327,101 / 7,211 - identical to A0 and A1.
-- WHY: everything since Phase 6 reads from the mart. This proves the mart
--      did not drift from the source.
-- RUNTIME: ~2 minutes
-- ============================================================================
WITH raw_latest AS (
    SELECT p.NAME_CONTRACT_STATUS, p.SK_DPD
    FROM pos_cash_balance p
    JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM pos_cash_balance GROUP BY SK_ID_PREV) m
      ON m.SK_ID_PREV=p.SK_ID_PREV AND m.mb=p.MONTHS_BALANCE
    UNION ALL
    SELECT c.NAME_CONTRACT_STATUS, c.SK_DPD
    FROM credit_card_balance c
    JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM credit_card_balance GROUP BY SK_ID_PREV) m
      ON m.SK_ID_PREV=c.SK_ID_PREV AND m.mb=c.MONTHS_BALANCE
)
SELECT COUNT(*)                                      AS accounts_from_raw,
       SUM(NAME_CONTRACT_STATUS='Active')            AS active_from_raw,
       SUM(NAME_CONTRACT_STATUS='Active' AND SK_DPD>0) AS delinquent_from_raw
FROM raw_latest;


-- ############################################################################
--  END. See docs/13_executive_summary.md for what all of this means.
-- ############################################################################
