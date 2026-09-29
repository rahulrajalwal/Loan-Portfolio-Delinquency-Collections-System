-- =====================================================================
-- PHASE 7 - DELINQUENCY & REPAYMENT BEHAVIOUR   (modules M4, M5, M6)
--
-- Everything is measured against the observed outcome where possible.
-- Base rate: TARGET = 8.0729% on 307,511 train customers. Any signal must be
-- read against that, and every rate is published with its denominator.
--
-- [D4] resolved in Phase 6:
--   FIRST-PAYMENT lateness  = the RISK signal      (1.88x lift vs 1.33x)
--   SETTLEMENT lateness     = the EXPOSURE measure (what is still owed)
-- Step 0 materialises the first-payment signal so no later phase re-scans
-- the 12.9M-row installment table.
-- =====================================================================
USE loan_portfolio;

-- ---------------------------------------------------------------------
-- STEP 0 - materialise first-payment lateness into mart_customer
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS tmp_first_late;
CREATE TABLE tmp_first_late AS
SELECT SK_ID_CURR,
       SUM(DAYS_LATE_FIRST >  0)                                  AS N_LATE_FIRST,
       SUM(DAYS_LATE_FIRST > 30)                                  AS N_LATE_FIRST_30PLUS,
       ROUND(100.0*SUM(DAYS_LATE_FIRST > 0)/COUNT(*), 3)          AS PCT_LATE_FIRST,
       MAX(DAYS_LATE_FIRST)                                       AS MAX_DAYS_LATE_FIRST
FROM stg_installment
WHERE DAY_FIRST_PAYMENT IS NOT NULL
GROUP BY SK_ID_CURR;
ALTER TABLE tmp_first_late ADD PRIMARY KEY (SK_ID_CURR);

ALTER TABLE mart_customer
  ADD COLUMN N_LATE_FIRST         INT           NULL,
  ADD COLUMN N_LATE_FIRST_30PLUS  INT           NULL,
  ADD COLUMN PCT_LATE_FIRST       DECIMAL(8,3)  NULL,
  ADD COLUMN MAX_DAYS_LATE_FIRST  INT           NULL;

UPDATE mart_customer m JOIN tmp_first_late t ON t.SK_ID_CURR = m.SK_ID_CURR
SET m.N_LATE_FIRST        = t.N_LATE_FIRST,
    m.N_LATE_FIRST_30PLUS = t.N_LATE_FIRST_30PLUS,
    m.PCT_LATE_FIRST      = t.PCT_LATE_FIRST,
    m.MAX_DAYS_LATE_FIRST = t.MAX_DAYS_LATE_FIRST;
DROP TABLE tmp_first_late;


SELECT '======== R1  REPAYMENT BEHAVIOUR ACROSS THE BOOK ========' AS section;
-- Q: how do customers actually repay, and does it track the outcome?
-- Grain: one row per customer. Only train customers have an outcome.
SELECT CASE WHEN PCT_LATE_FIRST IS NULL      THEN 'no installment history'
            WHEN PCT_LATE_FIRST =  0         THEN 'never late'
            WHEN PCT_LATE_FIRST <=  5        THEN 'late <=5% of installments'
            WHEN PCT_LATE_FIRST <= 15        THEN 'late 5-15%'
            WHEN PCT_LATE_FIRST <= 30        THEN 'late 15-30%'
            ELSE 'late >30%' END                                AS repayment_band,
       COUNT(*)                                                 AS customers,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 2)           AS pct_of_book,
       SUM(TARGET)                                              AS defaults,
       ROUND(100.0*AVG(TARGET), 3)                              AS target_rate_pct,
       ROUND(AVG(TARGET)/0.080729, 2)                           AS lift_vs_base
FROM mart_customer WHERE SOURCE='train'
GROUP BY repayment_band
ORDER BY target_rate_pct DESC;


SELECT '======== R2  CHRONIC vs OCCASIONAL LATENESS ========' AS section;
-- Q: does the COUNT of serious late events matter beyond the rate?
-- A customer late once may have had a bad month; late repeatedly is a pattern.
SELECT CASE WHEN N_LATE_FIRST_30PLUS IS NULL THEN 'no history'
            WHEN N_LATE_FIRST_30PLUS = 0     THEN '0'
            WHEN N_LATE_FIRST_30PLUS = 1     THEN '1'
            WHEN N_LATE_FIRST_30PLUS <= 3    THEN '2-3'
            WHEN N_LATE_FIRST_30PLUS <= 6    THEN '4-6'
            ELSE '7+' END                                       AS n_serious_late,
       COUNT(*)                                                 AS customers,
       SUM(TARGET)                                              AS defaults,
       ROUND(100.0*AVG(TARGET), 3)                              AS target_rate_pct,
       ROUND(AVG(TARGET)/0.080729, 2)                           AS lift_vs_base
FROM mart_customer WHERE SOURCE='train'
GROUP BY n_serious_late ORDER BY target_rate_pct DESC;


SELECT '======== R3  SHORTFALL - WHO UNDERPAYS? ========' AS section;
-- Q: distinct from lateness, does paying LESS than due predict the outcome?
-- Uses SUM(AMT_PAYMENT) per installment (finding Q1) - never row-by-row.
SELECT CASE WHEN N_SHORTFALL IS NULL THEN 'no history'
            WHEN N_SHORTFALL = 0     THEN 'never short'
            WHEN N_SHORTFALL = 1     THEN '1 installment short'
            WHEN N_SHORTFALL <= 5    THEN '2-5 short'
            ELSE '6+ short' END                                 AS shortfall_band,
       COUNT(*)                                                 AS customers,
       SUM(TARGET)                                              AS defaults,
       ROUND(100.0*AVG(TARGET), 3)                              AS target_rate_pct,
       ROUND(AVG(TARGET)/0.080729, 2)                           AS lift_vs_base,
       ROUND(AVG(TOTAL_SHORTFALL), 0)                           AS avg_total_shortfall
FROM mart_customer WHERE SOURCE='train'
GROUP BY shortfall_band ORDER BY target_rate_pct DESC;


SELECT '======== R4  DELINQUENCY SEVERITY vs EXPOSURE ========' AS section;
-- Q: is the money concentrated in the mild buckets or the severe ones?
-- This is the core input to collections prioritisation: severity alone is not
-- the same as money at risk.
SELECT BUCKET_REPORTING,
       COUNT(*)                                     AS accounts,
       ROUND(SUM(EXPOSURE)/1000000, 1)              AS exposure_millions,
       ROUND(AVG(EXPOSURE), 0)                      AS mean_exposure,
       ROUND(MAX(EXPOSURE), 0)                      AS max_exposure,
       SUM(EXPOSURE IS NULL)                        AS exposure_unknown
FROM mart_account WHERE IS_ACTIVE = 1 AND DPD_NOW > 0
GROUP BY BUCKET_REPORTING ORDER BY BUCKET_REPORTING;


SELECT '======== R5  UTILISATION vs DELINQUENCY (cards) ========' AS section;
-- Q: does running close to the limit precede missed payments?
-- Concept A8: utilisation is a LEADING indicator; DPD is lagging.
-- Cards only - POS/cash loans have no credit limit.
SELECT CASE WHEN MAX_UTILISATION IS NULL THEN 'no limit recorded'
            WHEN MAX_UTILISATION <= 0.30 THEN '0-30%'
            WHEN MAX_UTILISATION <= 0.60 THEN '30-60%'
            WHEN MAX_UTILISATION <= 0.90 THEN '60-90%'
            WHEN MAX_UTILISATION <= 1.00 THEN '90-100%'
            ELSE 'over limit' END                            AS utilisation_band,
       COUNT(*)                                              AS accounts,
       SUM(DPD_NOW > 0)                                      AS delinquent_now,
       ROUND(100.0*SUM(DPD_NOW > 0)/COUNT(*), 3)             AS delinquency_rate_pct,
       SUM(MAX_DPD_EVER > 0)                                 AS ever_delinquent,
       ROUND(100.0*SUM(MAX_DPD_EVER > 0)/COUNT(*), 3)        AS ever_delinquent_pct
FROM mart_account WHERE PRODUCT='CARD' AND IS_ACTIVE = 1
GROUP BY utilisation_band ORDER BY utilisation_band;


SELECT '======== R6  DETERIORATION MOMENTUM ========' AS section;
-- Q: does recent worsening (last 3 months vs the 3 before) matter beyond level?
-- Concept A6: momentum, not just position on the ladder.
SELECT a.IS_DETERIORATING,
       COUNT(*)                                        AS accounts,
       ROUND(100.0*SUM(a.DPD_NOW > 0)/COUNT(*), 3)     AS delinquency_rate_pct,
       ROUND(AVG(a.EXPOSURE), 0)                       AS mean_exposure,
       COUNT(c.TARGET)                                 AS train_customers,
       ROUND(100.0*AVG(c.TARGET), 3)                   AS target_rate_pct
FROM mart_account a
LEFT JOIN mart_customer c ON c.SK_ID_CURR = a.SK_ID_CURR AND c.SOURCE='train'
WHERE a.IS_ACTIVE = 1
GROUP BY a.IS_DETERIORATING;


SELECT '======== R7  PERSISTENCE OF DELINQUENCY ========' AS section;
-- Q: among accounts that ever went late, how LONG did they stay late?
-- Distinguishes a one-month slip from a chronic state.
SELECT CASE WHEN MONTHS_DELINQUENT = 0  THEN '0 - never'
            WHEN MONTHS_DELINQUENT = 1  THEN '1 month'
            WHEN MONTHS_DELINQUENT <= 3 THEN '2-3 months'
            WHEN MONTHS_DELINQUENT <= 6 THEN '4-6 months'
            WHEN MONTHS_DELINQUENT <=12 THEN '7-12 months'
            ELSE '12+ months' END                            AS months_delinquent_band,
       COUNT(*)                                              AS accounts,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 3)        AS pct_of_accounts,
       ROUND(AVG(MAX_DPD_EVER), 0)                           AS avg_worst_dpd,
       SUM(IS_ACTIVE)                                        AS still_active
FROM mart_account
GROUP BY months_delinquent_band ORDER BY accounts DESC;


SELECT '======== R8  DO SIGNALS STACK? (preview of M10) ========' AS section;
-- Q: do independent behavioural signals combine, or are they the same signal
--    wearing different hats?  This is the honest test before building any
--    scoring framework in Phase 9.
SELECT (N_LATE_FIRST_30PLUS > 0)          AS sig_late,
       (N_SHORTFALL > 0)                  AS sig_shortfall,
       (N_BUREAU_OVERDUE > 0)             AS sig_bureau,
       COUNT(*)                           AS customers,
       SUM(TARGET)                        AS defaults,
       ROUND(100.0*AVG(TARGET), 3)        AS target_rate_pct,
       ROUND(AVG(TARGET)/0.080729, 2)     AS lift_vs_base
FROM mart_customer
WHERE SOURCE='train' AND N_LATE_FIRST_30PLUS IS NOT NULL
GROUP BY sig_late, sig_shortfall, sig_bureau
ORDER BY target_rate_pct DESC;
