-- =====================================================================
-- PHASE 10 - COLLECTIONS PRIORITISATION   (module M12)
--
-- WHAT THIS IS:   a ranking of the delinquent live book by where value is
--                 concentrated, using two MEASURED inputs:
--                   * EXPOSURE            (Phase 6/7)
--                   * observed CURE RATE  (Phase 8 roll rates)
--
-- WHAT THIS IS NOT:
--   * not a prediction of recovery
--   * not a claim that contacting an account causes it to cure
--   The cure rates are observed NATURAL month-to-month transitions across the
--   whole panel. No intervention data exists in this dataset. So the framework
--   says "this is where curable money sits", never "we will recover this".
--
-- WHY NOT SORT BY DPD (the finding that drives the whole design):
--   Phase 7 R4 measured the delinquent live book:
--     bucket 1-30   : 5,163 accounts holding  465.7M  (mean 91,648)
--     bucket 360+   : 1,369 accounts holding    0.2M  (mean    179)
--   Sorting by DPD descending works 1,369 accounts holding almost nothing,
--   while ignoring 5,163 accounts holding 2,300x more money.
--   Phase 8 V4 then showed cure collapses past 90 days (4-7% vs 55-59%).
--   Severity is therefore the WORST available sort key.
-- =====================================================================
USE loan_portfolio;

-- ---------------------------------------------------------------------
-- C1 - measured cure rates per product x bucket, straight from the panel
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart_cure_rate;
CREATE TABLE mart_cure_rate AS
WITH ord AS (
    SELECT PRODUCT, from_bucket, to_bucket, transitions,
           FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+') AS f_ord,
           FIELD(to_bucket,  '0-current','1-30','31-90','91-360','360+') AS t_ord
    FROM mart_roll_rate
)
SELECT PRODUCT,
       from_bucket                                                          AS bucket,
       SUM(transitions)                                                     AS observed_transitions,
       ROUND(SUM(CASE WHEN t_ord < f_ord THEN transitions ELSE 0 END)
             / SUM(transitions), 5)                                         AS cure_rate,
       ROUND(SUM(CASE WHEN t_ord > f_ord THEN transitions ELSE 0 END)
             / SUM(transitions), 5)                                         AS forward_rate
FROM ord GROUP BY PRODUCT, from_bucket;
ALTER TABLE mart_cure_rate ADD PRIMARY KEY (PRODUCT, bucket);

SELECT '======== C1  MEASURED CURE RATES (the ranking input) ========' AS section;
SELECT PRODUCT, bucket, observed_transitions,
       ROUND(100*cure_rate,3) AS cure_pct, ROUND(100*forward_rate,3) AS forward_pct
FROM mart_cure_rate
ORDER BY PRODUCT, FIELD(bucket,'0-current','1-30','31-90','91-360','360+');


-- ---------------------------------------------------------------------
-- C2 - rebuild the queue with the analytical bucket + priority
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart_collections_queue;
CREATE TABLE mart_collections_queue AS
SELECT
    ma.SK_ID_PREV, ma.PRODUCT, ma.SK_ID_CURR,
    ma.DPD_NOW, ma.DPD_DEF_NOW,
    ma.BUCKET_REPORTING, ma.BUCKET_ANALYTICAL,
    ma.EXPOSURE, ma.EXPOSURE_IS_PROXY, ma.UTILISATION,
    ma.MONTHS_DELINQUENT, ma.MAX_DPD_EVER, ma.IS_DETERIORATING,
    cr.cure_rate,
    -- CURE-WEIGHTED EXPOSURE: money at risk, weighted by how often accounts in
    -- this bucket historically move to a better bucket. Deliberately NOT called
    -- "expected recovery" - no intervention data exists.
    ROUND(COALESCE(ma.EXPOSURE,0) * COALESCE(cr.cure_rate,0), 2)  AS cure_weighted_exposure,
    -- [D3] materiality: still delinquent once trivial balances are ignored?
    CASE WHEN ma.DPD_DEF_NOW > 0 THEN 1 ELSE 0 END                AS IS_MATERIAL,
    -- chronic vs first-time
    CASE WHEN ma.MONTHS_DELINQUENT >= 3 THEN 1 ELSE 0 END         AS IS_CHRONIC,
    mc.AGE_YEARS, mc.NAME_INCOME_TYPE, mc.AMT_INCOME_TOTAL,
    mc.PCT_LATE_FIRST, mc.N_LATE_FIRST_30PLUS, mc.N_BUREAU_OVERDUE, mc.TARGET
FROM mart_account ma
JOIN mart_customer mc ON mc.SK_ID_CURR = ma.SK_ID_CURR
LEFT JOIN mart_cure_rate cr ON cr.PRODUCT = ma.PRODUCT AND cr.bucket = ma.BUCKET_ANALYTICAL
WHERE ma.IS_ACTIVE = 1 AND ma.DPD_NOW > 0;

ALTER TABLE mart_collections_queue
  ADD PRIMARY KEY (SK_ID_PREV, PRODUCT),
  ADD INDEX ix_q_value (cure_weighted_exposure);


SELECT '======== C2  WHY SEVERITY IS THE WRONG SORT KEY ========' AS section;
-- Side by side: the same 7,211 accounts, ranked two ways.
SELECT BUCKET_ANALYTICAL,
       COUNT(*)                                                   AS accounts,
       ROUND(SUM(EXPOSURE)/1000000, 2)                            AS exposure_m,
       ROUND(100.0*SUM(EXPOSURE)/SUM(SUM(EXPOSURE)) OVER (), 2)   AS pct_of_exposure,
       ROUND(AVG(cure_rate)*100, 2)                               AS cure_pct,
       ROUND(SUM(cure_weighted_exposure)/1000000, 2)              AS cure_wtd_exposure_m,
       ROUND(100.0*SUM(cure_weighted_exposure)
             /SUM(SUM(cure_weighted_exposure)) OVER (), 2)        AS pct_of_curable_value
FROM mart_collections_queue
GROUP BY BUCKET_ANALYTICAL
ORDER BY FIELD(BUCKET_ANALYTICAL,'1-30','31-90','91-360','360+');


-- ---------------------------------------------------------------------
-- C3 - priority tiers.  Every rule stated in plain language.
-- ---------------------------------------------------------------------
SELECT '======== C3  PRIORITY TIERS ========' AS section;
-- P1 CRITICAL : top-quintile curable value AND deteriorating  -> act now
-- P2 HIGH     : top-quintile curable value                    -> work this week
-- P3 MEDIUM   : material, curable bucket, mid value           -> standard queue
-- P4 LOW      : immaterial (trivial balance) or already deep  -> monitor only
-- P5 RECOVERY : 360+ - not a collections case, a recovery case
DROP TABLE IF EXISTS mart_queue_tiered;
CREATE TABLE mart_queue_tiered AS
WITH q AS (
    SELECT *,
           NTILE(5) OVER (ORDER BY cure_weighted_exposure DESC) AS value_quintile
    FROM mart_collections_queue
)
SELECT *,
       CASE
         WHEN BUCKET_ANALYTICAL = '360+'                              THEN 'P5 recovery (not collections)'
         WHEN value_quintile = 1 AND IS_DETERIORATING = 1             THEN 'P1 critical'
         WHEN value_quintile = 1                                      THEN 'P2 high'
         WHEN IS_MATERIAL = 1 AND BUCKET_ANALYTICAL IN ('1-30','31-90') THEN 'P3 medium'
         ELSE                                                              'P4 low / monitor'
       END AS priority_tier
FROM q;
ALTER TABLE mart_queue_tiered ADD PRIMARY KEY (SK_ID_PREV, PRODUCT);

SELECT priority_tier,
       COUNT(*)                                                        AS accounts,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 2)                  AS pct_of_queue,
       ROUND(SUM(EXPOSURE)/1000000, 2)                                 AS exposure_m,
       ROUND(SUM(cure_weighted_exposure)/1000000, 2)                   AS curable_value_m,
       ROUND(100.0*SUM(cure_weighted_exposure)
             /SUM(SUM(cure_weighted_exposure)) OVER (), 2)             AS pct_curable_value,
       ROUND(AVG(DPD_NOW), 0)                                          AS avg_dpd,
       SUM(IS_MATERIAL)                                                AS n_material
FROM mart_queue_tiered
GROUP BY priority_tier ORDER BY priority_tier;


SELECT '======== C4  DOES THE TIERING CONCENTRATE VALUE? ========' AS section;
-- The test of any prioritisation: does working the top slice reach most of the
-- value?  Compare against sorting by DPD, the naive alternative.
WITH ranked AS (
    SELECT cure_weighted_exposure, EXPOSURE,
           ROW_NUMBER() OVER (ORDER BY cure_weighted_exposure DESC) AS rn_value,
           ROW_NUMBER() OVER (ORDER BY DPD_NOW DESC)                AS rn_dpd,
           COUNT(*) OVER ()                                         AS n,
           SUM(cure_weighted_exposure) OVER ()                      AS total_value
    FROM mart_collections_queue
)
SELECT pct_worked,
       ROUND(100.0*SUM(CASE WHEN rn_value <= n*pct_worked/100 THEN cure_weighted_exposure ELSE 0 END)
             /MAX(total_value), 2)  AS pct_value_reached_by_VALUE_sort,
       ROUND(100.0*SUM(CASE WHEN rn_dpd   <= n*pct_worked/100 THEN cure_weighted_exposure ELSE 0 END)
             /MAX(total_value), 2)  AS pct_value_reached_by_DPD_sort
FROM ranked
CROSS JOIN (SELECT 5 AS pct_worked UNION SELECT 10 UNION SELECT 20
            UNION SELECT 30 UNION SELECT 50) p
GROUP BY pct_worked ORDER BY pct_worked;


SELECT '======== C5  THE QUEUE - top 15 accounts ========' AS section;
-- Small enough to inspect by hand, which is the point.
SELECT SK_ID_PREV, PRODUCT, BUCKET_ANALYTICAL, DPD_NOW,
       ROUND(EXPOSURE,0)               AS exposure,
       EXPOSURE_IS_PROXY               AS exp_is_proxy,
       ROUND(cure_rate*100,1)          AS cure_pct,
       ROUND(cure_weighted_exposure,0) AS curable_value,
       IS_DETERIORATING, IS_MATERIAL, IS_CHRONIC, priority_tier
FROM mart_queue_tiered
ORDER BY cure_weighted_exposure DESC LIMIT 15;


SELECT '======== C6  SANITY CHECK vs THE OUTCOME ========' AS section;
-- Not validation of recovery (impossible - no outcome data). This asks a
-- narrower question: do higher-priority tiers contain riskier BORROWERS,
-- measured by the one outcome we do have?  Train customers only.
SELECT priority_tier,
       COUNT(TARGET)                        AS train_customers,
       ROUND(100.0*AVG(TARGET), 3)          AS target_pct,
       ROUND(AVG(TARGET)/0.080729, 2)       AS lift_vs_base
FROM mart_queue_tiered WHERE TARGET IS NOT NULL
GROUP BY priority_tier ORDER BY priority_tier;
