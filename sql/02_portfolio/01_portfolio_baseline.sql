-- =====================================================================
-- PHASE 6 - PORTFOLIO BASELINE  (module M1)   [runs against the MART]
--
-- THE OBSERVATION POINT
-- ---------------------
-- This dataset has no calendar dates. MONTHS_BALANCE = -1 means "one month
-- before THAT customer's application", so there is no common as-of date.
--
-- What IS precisely defined: each account's LATEST OBSERVED MONTH - the month
-- immediately before its owner came back asking for new credit. That is a
-- coherent business moment (the state of a customer's existing credit at the
-- point of a new application) and it is what "the book" means here.
--
-- It is a RELATIVE-TIME snapshot, not a calendar one. Stated wherever used.
-- =====================================================================
USE loan_portfolio;

SELECT '======== P1  BOOK SIZE AND COMPOSITION ========' AS section;
-- Q: how big is the book and what is it made of?
-- Grain: one row per account (SK_ID_PREV, PRODUCT) at its latest observed month.
SELECT PRODUCT,
       COUNT(*)                                AS accounts_observed,
       SUM(IS_ACTIVE)                          AS accounts_active,
       ROUND(100.0*SUM(IS_ACTIVE)/COUNT(*), 2) AS pct_active,
       COUNT(DISTINCT SK_ID_CURR)              AS customers,
       ROUND(AVG(MONTHS_OBSERVED), 1)          AS avg_months_history
FROM mart_account
GROUP BY PRODUCT WITH ROLLUP;

-- Non-active accounts are NOT part of the live book. What are they?
SELECT PRODUCT, CONTRACT_STATUS, COUNT(*) AS accounts,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (PARTITION BY PRODUCT), 2) AS pct_of_product
FROM mart_account
GROUP BY PRODUCT, CONTRACT_STATUS
ORDER BY PRODUCT, accounts DESC;


SELECT '======== P2  EXPOSURE ========' AS section;
-- Q: how much money is on the book, and how much of it is a proxy?
-- POS exposure is DERIVED (CNT_INSTALMENT_FUTURE x AMT_ANNUITY) and includes
-- interest, not principal alone. CARD exposure is the real balance.
-- The two are reported separately and never silently summed.
SELECT PRODUCT,
       EXPOSURE_IS_PROXY,
       COUNT(*)                                       AS active_accounts,
       SUM(EXPOSURE IS NULL)                          AS exposure_unavailable,
       ROUND(100.0*SUM(EXPOSURE IS NULL)/COUNT(*), 2) AS pct_unavailable,
       ROUND(SUM(EXPOSURE)/1000000, 1)                AS exposure_millions,
       ROUND(AVG(EXPOSURE), 0)                        AS mean_exposure,
       ROUND(MAX(EXPOSURE), 0)                        AS max_exposure
FROM mart_account WHERE IS_ACTIVE = 1
GROUP BY PRODUCT, EXPOSURE_IS_PROXY;

-- Concentration: does a small share of accounts hold most of the money?
SELECT decile,
       COUNT(*)                        AS accounts,
       ROUND(SUM(EXPOSURE)/1000000, 1) AS exposure_millions,
       ROUND(100.0*SUM(EXPOSURE)/SUM(SUM(EXPOSURE)) OVER (), 2) AS pct_of_exposure,
       ROUND(MIN(EXPOSURE), 0)         AS min_in_decile,
       ROUND(MAX(EXPOSURE), 0)         AS max_in_decile
FROM (SELECT EXPOSURE, NTILE(10) OVER (ORDER BY EXPOSURE DESC) AS decile
      FROM mart_account WHERE IS_ACTIVE = 1 AND EXPOSURE > 0) t
GROUP BY decile ORDER BY decile;


SELECT '======== P3  DELINQUENCY OF THE LIVE BOOK ========' AS section;
-- Q: where does the active book sit on the DPD ladder, and how much exposure
--    sits in each bucket?  Counts published beside every rate.
SELECT PRODUCT, BUCKET_REPORTING,
       COUNT(*)                                                           AS accounts,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (PARTITION BY PRODUCT), 4) AS pct_accounts,
       ROUND(SUM(EXPOSURE)/1000000, 1)                                    AS exposure_millions,
       ROUND(100.0*SUM(EXPOSURE)/SUM(SUM(EXPOSURE)) OVER (PARTITION BY PRODUCT), 4) AS pct_exposure
FROM mart_account WHERE IS_ACTIVE = 1
GROUP BY PRODUCT, BUCKET_REPORTING
ORDER BY PRODUCT, BUCKET_REPORTING;

-- The headline numbers, each defined explicitly.
SELECT PRODUCT,
       COUNT(*)                                     AS active_accounts,
       SUM(DPD_NOW > 0)                             AS delinquent,
       ROUND(100.0*SUM(DPD_NOW > 0)/COUNT(*), 4)    AS delinquency_rate_pct,
       SUM(DPD_NOW > 90)                            AS npa_equivalent,
       ROUND(100.0*SUM(DPD_NOW > 90)/COUNT(*), 4)   AS npa_rate_pct,
       -- [D3] materiality filter: still delinquent once trivial balances ignored?
       SUM(DPD_DEF_NOW > 0)                         AS delinquent_material,
       ROUND(100.0*SUM(DPD_DEF_NOW > 0)/COUNT(*),4) AS delinquency_material_pct
FROM mart_account WHERE IS_ACTIVE = 1
GROUP BY PRODUCT WITH ROLLUP;

-- Snapshot vs history: the book looks healthier than the panel, because
-- accounts that deteriorate badly get closed and leave the Active set.
SELECT 'ever delinquent (whole history)' AS lens, COUNT(*) AS accounts,
       SUM(MAX_DPD_EVER > 0) AS n, ROUND(100.0*SUM(MAX_DPD_EVER>0)/COUNT(*),2) AS pct
FROM mart_account
UNION ALL
SELECT 'delinquent right now (live book)', SUM(IS_ACTIVE), SUM(IS_ACTIVE=1 AND DPD_NOW>0),
       ROUND(100.0*SUM(IS_ACTIVE=1 AND DPD_NOW>0)/SUM(IS_ACTIVE),2)
FROM mart_account;


SELECT '======== P4  BORROWER PROFILE ========' AS section;
-- Q: who holds this book, and does delinquency differ by segment?
-- HAVING suppresses groups too small to interpret - counts always shown.
SELECT c.NAME_INCOME_TYPE,
       COUNT(*)                                      AS active_accounts,
       COUNT(DISTINCT a.SK_ID_CURR)                  AS customers,
       ROUND(100.0*SUM(a.DPD_NOW > 0)/COUNT(*), 3)   AS delinquency_rate_pct,
       ROUND(SUM(a.EXPOSURE)/1000000, 1)             AS exposure_millions
FROM mart_account a JOIN mart_customer c ON c.SK_ID_CURR = a.SK_ID_CURR
WHERE a.IS_ACTIVE = 1
GROUP BY c.NAME_INCOME_TYPE HAVING customers >= 100
ORDER BY active_accounts DESC;

SELECT CASE WHEN c.AGE_YEARS < 30 THEN 'under 30' WHEN c.AGE_YEARS < 40 THEN '30-39'
            WHEN c.AGE_YEARS < 50 THEN '40-49'    WHEN c.AGE_YEARS < 60 THEN '50-59'
            ELSE '60+' END                            AS age_band,
       COUNT(*)                                       AS active_accounts,
       ROUND(100.0*SUM(a.DPD_NOW > 0)/COUNT(*), 3)    AS delinquency_rate_pct,
       ROUND(AVG(a.EXPOSURE), 0)                      AS mean_exposure
FROM mart_account a JOIN mart_customer c ON c.SK_ID_CURR = a.SK_ID_CURR
WHERE a.IS_ACTIVE = 1
GROUP BY age_band ORDER BY age_band;

-- Q4 treatment in action: the decoded not-employed flag.
SELECT c.FLAG_NOT_EMPLOYED,
       COUNT(*)                                       AS active_accounts,
       ROUND(100.0*SUM(a.DPD_NOW > 0)/COUNT(*), 3)    AS delinquency_rate_pct
FROM mart_account a JOIN mart_customer c ON c.SK_ID_CURR = a.SK_ID_CURR
WHERE a.IS_ACTIVE = 1 GROUP BY c.FLAG_NOT_EMPLOYED;


SELECT '======== P5  [D4] LATENESS DEFINITION ========' AS section;
-- Decision D4: is an installment "late" when the FIRST payment arrives, or when
-- it is FULLY SETTLED?  Both are materialised. This decides on evidence.
SELECT COUNT(*)                                              AS installments,
       SUM(N_PAYMENTS > 1)                                   AS split_installments,
       SUM(DAYS_LATE_FIRST   > 0)                            AS late_by_first,
       SUM(DAYS_LATE_SETTLED > 0)                            AS late_by_settlement,
       SUM(DAYS_LATE_SETTLED > 0) - SUM(DAYS_LATE_FIRST > 0) AS extra_under_settlement,
       ROUND(100.0*SUM(DAYS_LATE_FIRST   > 0)/COUNT(*), 4)   AS pct_late_first,
       ROUND(100.0*SUM(DAYS_LATE_SETTLED > 0)/COUNT(*), 4)   AS pct_late_settled
FROM stg_installment WHERE DAY_FIRST_PAYMENT IS NOT NULL;

-- Where do the two definitions disagree, and by how much?
SELECT CASE WHEN DAYS_LATE_FIRST <= 0 AND DAYS_LATE_SETTLED >  0 THEN 'early start, late finish'
            WHEN DAYS_LATE_FIRST >  0 AND DAYS_LATE_SETTLED >  0 THEN 'late on both'
            WHEN DAYS_LATE_FIRST <= 0 AND DAYS_LATE_SETTLED <= 0 THEN 'on time on both'
            ELSE 'other' END                                  AS agreement,
       COUNT(*)                                               AS installments,
       ROUND(AVG(N_PAYMENTS), 2)                              AS avg_payments,
       ROUND(AVG(DAYS_LATE_SETTLED - DAYS_LATE_FIRST), 1)     AS avg_gap_days
FROM stg_installment WHERE DAY_FIRST_PAYMENT IS NOT NULL
GROUP BY agreement ORDER BY installments DESC;

-- THE DECIDING TEST: which definition separates the observed outcome better?
-- Base rate is 8.0729%. The definition producing the wider gap carries more signal.
SELECT 'first-payment defn' AS definition,
       SUM(ever_late)                                             AS customers_flagged,
       ROUND(100.0*AVG(CASE WHEN ever_late=1 THEN TARGET END), 3) AS target_pct_flagged,
       ROUND(100.0*AVG(CASE WHEN ever_late=0 THEN TARGET END), 3) AS target_pct_not_flagged
FROM (SELECT s.SK_ID_CURR, MAX(s.DAYS_LATE_FIRST > 30) AS ever_late, MAX(a.TARGET) AS TARGET
      FROM stg_installment s JOIN application a ON a.SK_ID_CURR = s.SK_ID_CURR
      WHERE a.SOURCE='train' GROUP BY s.SK_ID_CURR) t
UNION ALL
SELECT 'settlement defn',
       SUM(ever_late),
       ROUND(100.0*AVG(CASE WHEN ever_late=1 THEN TARGET END), 3),
       ROUND(100.0*AVG(CASE WHEN ever_late=0 THEN TARGET END), 3)
FROM (SELECT s.SK_ID_CURR, MAX(s.DAYS_LATE_SETTLED > 30) AS ever_late, MAX(a.TARGET) AS TARGET
      FROM stg_installment s JOIN application a ON a.SK_ID_CURR = s.SK_ID_CURR
      WHERE a.SOURCE='train' GROUP BY s.SK_ID_CURR) t;
