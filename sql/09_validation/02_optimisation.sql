-- =====================================================================
-- PHASE 11C - QUERY OPTIMISATION CASE STUDIES  (+ the V-8 fix)
--
-- Honest accounting: one of these optimisations FAILED. It is included
-- because a failed optimisation with a measured explanation is worth more
-- than three successful ones with no diagnosis.
-- =====================================================================
USE loan_portfolio;

SELECT '======== V-8 (fixed)  COLLECTIONS VALUE CONCENTRATION ========' AS section;
-- The original query omitted its FROM clause. Corrected here.
WITH r AS (
    SELECT cure_weighted_exposure AS v,
           ROW_NUMBER() OVER (ORDER BY cure_weighted_exposure DESC) AS rn,
           COUNT(*)                        OVER () AS n,
           SUM(cure_weighted_exposure)     OVER () AS tot
    FROM mart_collections_queue
)
SELECT ROUND(100.0*SUM(CASE WHEN rn <= n*0.10 THEN v ELSE 0 END)/MAX(tot), 2) AS pct_value_top10_recomputed,
       79.82    AS phase10_reported,
       COUNT(*) AS queue_size
FROM r;


SELECT '======== OPT-1  ROLL RATE: the optimisation that FAILED ========' AS section;
-- HYPOTHESIS  The window partitions by SK_ID_PREV while the PK is
--             (SK_ID_PREV, PRODUCT, MONTHS_BALANCE). Aligning the partition to
--             the PK prefix should let InnoDB feed rows in order and skip the sort.
-- RESULT      Refuted. 253.4s vs 271.9s - no meaningful difference.
-- DIAGNOSIS   Both plans below show "Sort" over 13.2M rows. MySQL 8 always
--             materialises and sorts for a buffered window function; it will not
--             ride clustered-index order to avoid it. This is an engine
--             limitation, not a query-writing mistake, and no index fixes it.
EXPLAIN FORMAT=TREE
SELECT SK_ID_PREV,
       LAG(BUCKET_ANALYTICAL) OVER (PARTITION BY SK_ID_PREV ORDER BY MONTHS_BALANCE)
FROM stg_account_month;

EXPLAIN FORMAT=TREE
SELECT SK_ID_PREV,
       LAG(BUCKET_ANALYTICAL) OVER (PARTITION BY SK_ID_PREV, PRODUCT ORDER BY MONTHS_BALANCE)
FROM stg_account_month;


SELECT '======== OPT-2  ROLL RATE: what DID work - materialisation ========' AS section;
-- Since the sort cannot be avoided, stop paying for it repeatedly.
-- The transition matrix is 40 rows and only changes when the panel changes,
-- so it is computed once into mart_roll_rate and read thereafter.
EXPLAIN FORMAT=TREE
SELECT PRODUCT, from_bucket, to_bucket, transitions FROM mart_roll_rate;


SELECT '======== OPT-3  INDEX ON THE LIVE BOOK ========' AS section;
-- The dashboard's most frequent query: the active book split by bucket.
-- ix_ma_live (IS_ACTIVE, BUCKET_ANALYTICAL) should let InnoDB satisfy this
-- from the index alone. Compare the plans.
EXPLAIN FORMAT=TREE
SELECT BUCKET_ANALYTICAL, COUNT(*) FROM mart_account
WHERE IS_ACTIVE = 1 GROUP BY BUCKET_ANALYTICAL;

EXPLAIN FORMAT=TREE
SELECT BUCKET_ANALYTICAL, COUNT(*) FROM mart_account IGNORE INDEX (ix_ma_live)
WHERE IS_ACTIVE = 1 GROUP BY BUCKET_ANALYTICAL;


SELECT '======== OPT-4  FAN-OUT: the wrong way vs the right way ========' AS section;
-- The Phase 2 lesson, as an execution plan. Both queries answer
-- "total credit amount by income type", but the first fans out ~40x.
--
-- WRONG: joins customer to installment rows, multiplying AMT_CREDIT by the
--        number of payment events. Result is inflated AND slow.
EXPLAIN FORMAT=TREE
SELECT c.NAME_INCOME_TYPE, SUM(c.AMT_CREDIT)
FROM mart_customer c
JOIN stg_installment i ON i.SK_ID_CURR = c.SK_ID_CURR
GROUP BY c.NAME_INCOME_TYPE;

-- RIGHT: the customer grain already holds one row per customer. No join needed.
EXPLAIN FORMAT=TREE
SELECT NAME_INCOME_TYPE, SUM(AMT_CREDIT)
FROM mart_customer
GROUP BY NAME_INCOME_TYPE;

-- And the size of the error, measured:
SELECT 'correct (customer grain)' AS method,
       ROUND(SUM(AMT_CREDIT)/1000000000, 2) AS total_credit_billions,
       COUNT(*)                             AS rows_aggregated
FROM mart_customer
UNION ALL
SELECT 'fanned out (joined to installments)',
       ROUND(SUM(c.AMT_CREDIT)/1000000000, 2),
       COUNT(*)
FROM mart_customer c JOIN stg_installment i ON i.SK_ID_CURR = c.SK_ID_CURR;
