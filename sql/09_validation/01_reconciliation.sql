-- =====================================================================
-- PHASE 11A - RECONCILIATION
--
-- Rule: every headline number is re-derived from the BASE tables, by a
-- different query path than the one that produced it. If the two disagree,
-- the number is wrong regardless of how plausible it looked.
--
-- The mart was built once and everything since Phase 6 reads from it. That is
-- efficient but it means a single build error would silently propagate through
-- five phases. This is the check for that.
-- =====================================================================
USE loan_portfolio;

SELECT '======== V-1  ROW COUNTS: what is actually in the database now ========' AS section;
SELECT 'application'            AS tbl, COUNT(*) AS rows_now, 356255   AS expected FROM application
UNION ALL SELECT 'bureau',              COUNT(*), 1716428 FROM bureau
UNION ALL SELECT 'previous_application',COUNT(*), 1670214 FROM previous_application
UNION ALL SELECT 'pos_cash_balance',    COUNT(*),10001358 FROM pos_cash_balance
UNION ALL SELECT 'credit_card_balance', COUNT(*), 3840312 FROM credit_card_balance
UNION ALL SELECT 'installments_payments',COUNT(*),13605401 FROM installments_payments
UNION ALL SELECT 'bureau_balance (DROPPED)', 0,          0;


SELECT '======== V-2  BOOK: mart_account vs the raw panels ========' AS section;
-- Independent path: rebuild the "latest month per account" directly from
-- pos_cash_balance and credit_card_balance, never touching stg_ or mart_.
WITH raw_latest AS (
    SELECT 'POS' AS PRODUCT, p.SK_ID_PREV, p.NAME_CONTRACT_STATUS, p.SK_DPD
    FROM pos_cash_balance p
    JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM pos_cash_balance GROUP BY SK_ID_PREV) m
      ON m.SK_ID_PREV = p.SK_ID_PREV AND m.mb = p.MONTHS_BALANCE
    UNION ALL
    SELECT 'CARD', c.SK_ID_PREV, c.NAME_CONTRACT_STATUS, c.SK_DPD
    FROM credit_card_balance c
    JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM credit_card_balance GROUP BY SK_ID_PREV) m
      ON m.SK_ID_PREV = c.SK_ID_PREV AND m.mb = c.MONTHS_BALANCE
)
SELECT 'accounts at latest month' AS metric,
       (SELECT COUNT(*) FROM raw_latest)                                   AS from_raw_tables,
       (SELECT COUNT(*) FROM mart_account)                                 AS from_mart,
       (SELECT COUNT(*) FROM raw_latest) - (SELECT COUNT(*) FROM mart_account) AS diff;

WITH raw_latest AS (
    SELECT p.NAME_CONTRACT_STATUS, p.SK_DPD
    FROM pos_cash_balance p
    JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM pos_cash_balance GROUP BY SK_ID_PREV) m
      ON m.SK_ID_PREV = p.SK_ID_PREV AND m.mb = p.MONTHS_BALANCE
    UNION ALL
    SELECT c.NAME_CONTRACT_STATUS, c.SK_DPD
    FROM credit_card_balance c
    JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM credit_card_balance GROUP BY SK_ID_PREV) m
      ON m.SK_ID_PREV = c.SK_ID_PREV AND m.mb = c.MONTHS_BALANCE
)
SELECT 'active accounts'  AS metric,
       SUM(NAME_CONTRACT_STATUS='Active')                              AS from_raw_tables,
       (SELECT SUM(IS_ACTIVE) FROM mart_account)                       AS from_mart,
       SUM(NAME_CONTRACT_STATUS='Active') - (SELECT SUM(IS_ACTIVE) FROM mart_account) AS diff
FROM raw_latest
UNION ALL
SELECT 'delinquent active accounts (the queue)',
       SUM(NAME_CONTRACT_STATUS='Active' AND SK_DPD > 0),
       (SELECT COUNT(*) FROM mart_queue_tiered),
       SUM(NAME_CONTRACT_STATUS='Active' AND SK_DPD > 0) - (SELECT COUNT(*) FROM mart_queue_tiered)
FROM raw_latest;


SELECT '======== V-3  EXPOSURE: rebuilt from raw, both products ========' AS section;
-- CARD exposure is AMT_BALANCE directly. POS exposure is the derived proxy
-- CNT_INSTALMENT_FUTURE x AMT_ANNUITY. Both recomputed from source here.
SELECT 'CARD exposure (raw AMT_BALANCE)' AS metric,
       ROUND(SUM(c.AMT_BALANCE)/1000000, 1)                                  AS from_raw_millions,
       (SELECT ROUND(SUM(EXPOSURE)/1000000,1) FROM mart_account
        WHERE PRODUCT='CARD' AND IS_ACTIVE=1)                                AS from_mart_millions
FROM credit_card_balance c
JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM credit_card_balance GROUP BY SK_ID_PREV) m
  ON m.SK_ID_PREV=c.SK_ID_PREV AND m.mb=c.MONTHS_BALANCE
WHERE c.NAME_CONTRACT_STATUS='Active';

SELECT 'POS exposure (proxy rebuilt from raw)' AS metric,
       ROUND(SUM(p.CNT_INSTALMENT_FUTURE * pa.AMT_ANNUITY)/1000000, 1)       AS from_raw_millions,
       (SELECT ROUND(SUM(EXPOSURE)/1000000,1) FROM mart_account
        WHERE PRODUCT='POS' AND IS_ACTIVE=1)                                 AS from_mart_millions
FROM pos_cash_balance p
JOIN (SELECT SK_ID_PREV, MAX(MONTHS_BALANCE) mb FROM pos_cash_balance GROUP BY SK_ID_PREV) m
  ON m.SK_ID_PREV=p.SK_ID_PREV AND m.mb=p.MONTHS_BALANCE
JOIN previous_application pa ON pa.SK_ID_PREV=p.SK_ID_PREV
WHERE p.NAME_CONTRACT_STATUS='Active';


SELECT '======== V-4  OUTCOME: base rate from source ========' AS section;
SELECT 'TARGET base rate' AS metric,
       (SELECT ROUND(100.0*AVG(TARGET),4) FROM application WHERE SOURCE='train')     AS from_application,
       (SELECT ROUND(100.0*AVG(TARGET),4) FROM mart_customer WHERE SOURCE='train')   AS from_mart,
       (SELECT COUNT(*) FROM application WHERE SOURCE='train')                       AS n_application,
       (SELECT COUNT(*) FROM mart_customer WHERE SOURCE='train')                     AS n_mart;


SELECT '======== V-5  GRAIN: split payments re-derived ========' AS section;
SELECT 'split payments (F1)' AS metric,
       (SELECT COUNT(*) - COUNT(DISTINCT SK_ID_PREV, NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER)
        FROM installments_payments)                                          AS from_raw,
       653483                                                                AS phase2_measured,
       (SELECT COUNT(*) FROM installments_payments)
       - (SELECT COUNT(*) FROM stg_installment)                              AS implied_by_staging;


SELECT '======== V-6  ROLL RATE: one cell recomputed independently ========' AS section;
-- Recompute POS 1-30 -> 31-90 straight from stg_account_month and compare to
-- the stored matrix. Different query, same answer expected.
WITH seq AS (
    SELECT SK_ID_PREV, MONTHS_BALANCE, BUCKET_ANALYTICAL,
           LAG(BUCKET_ANALYTICAL) OVER (PARTITION BY SK_ID_PREV ORDER BY MONTHS_BALANCE) pb,
           LAG(MONTHS_BALANCE)    OVER (PARTITION BY SK_ID_PREV ORDER BY MONTHS_BALANCE) pm
    FROM stg_account_month WHERE PRODUCT='POS'
)
SELECT 'POS 1-30 -> 31-90' AS transition,
       SUM(pb='1-30' AND BUCKET_ANALYTICAL='31-90' AND MONTHS_BALANCE=pm+1) AS recomputed,
       (SELECT transitions FROM mart_roll_rate
        WHERE PRODUCT='POS' AND from_bucket='1-30' AND to_bucket='31-90')    AS stored_value,
       SUM(pb='1-30' AND MONTHS_BALANCE=pm+1)                                AS recomputed_denominator,
       (SELECT SUM(transitions) FROM mart_roll_rate
        WHERE PRODUCT='POS' AND from_bucket='1-30')                          AS stored_denominator
FROM seq WHERE pb IS NOT NULL;


SELECT '======== V-7  SIGNAL COUNTS: Phase 9 re-derived from source ========' AS section;
-- S3 (bureau overdue) rebuilt straight from the bureau table.
SELECT 'S3 bureau overdue' AS signal_name,
       (SELECT COUNT(DISTINCT b.SK_ID_CURR) FROM bureau b
        JOIN application a ON a.SK_ID_CURR=b.SK_ID_CURR AND a.SOURCE='train'
        WHERE b.CREDIT_DAY_OVERDUE > 0)                                      AS from_raw,
       (SELECT COUNT(*) FROM mart_customer
        WHERE SOURCE='train' AND N_BUREAU_OVERDUE > 0)                       AS from_mart;

-- S1 (ever 30+ late, first-payment) rebuilt from stg_installment.
SELECT 'S1 ever 30+ late' AS signal_name,
       (SELECT COUNT(*) FROM (SELECT s.SK_ID_CURR FROM stg_installment s
        JOIN application a ON a.SK_ID_CURR=s.SK_ID_CURR AND a.SOURCE='train'
        GROUP BY s.SK_ID_CURR HAVING MAX(s.DAYS_LATE_FIRST) > 30) x)         AS from_raw,
       (SELECT COUNT(*) FROM mart_customer
        WHERE SOURCE='train' AND N_LATE_FIRST_30PLUS > 0)                    AS from_mart;


SELECT '======== V-8  COLLECTIONS: value concentration re-derived ========' AS section;
-- Rebuild the C4 headline (top 10% by value reaches 79.82%) without the
-- tiered table, using only mart_collections_queue.
WITH r AS (SELECT cure_weighted_exposure v,
                  ROW_NUMBER() OVER (ORDER BY cure_weighted_exposure DESC) rn,
                  COUNT(*) OVER () n, SUM(cure_weighted_exposure) OVER () tot
           FROM mart_collections_queue)
SELECT ROUND(100.0*SUM(CASE WHEN rn <= n*0.10 THEN v ELSE 0 END)/MAX(tot),2) AS pct_value_top10_recomputed,
       79.82                                                                 AS phase10_reported,
       COUNT(*)                                                              AS queue_size;
