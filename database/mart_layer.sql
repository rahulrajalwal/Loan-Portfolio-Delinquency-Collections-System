-- =====================================================================
-- MART LAYER  (post re-evaluation, 2026-09-07)
--
-- DECISION: keep Home Credit, minimum evidence-based reduction.
--   * DROP bureau_balance (27,299,925 rows, 47% of the database).
--     Justification: its unique contribution is an EXTERNAL monthly delinquency
--     panel, which duplicates what pos_cash_balance and credit_card_balance
--     already provide internally. No module in M1-M13 depends on it alone.
--   * KEEP bureau (1.7M rows) - cheap, and carries external credit signals
--     (CREDIT_ACTIVE, AMT_CREDIT_SUM_OVERDUE, CREDIT_DAY_OVERDUE) that feed
--     the early-warning module.
--
-- PURPOSE OF THIS LAYER
--   Every expensive panel computation runs ONCE, here. Afterwards all analysis
--   runs against tables of <= 1.05M rows, which are fast and inspectable.
--   Measured before: roll-rate LAG over 13.8M rows = 275.7s PER QUERY.
--   That cost is inherent to MySQL window functions and cannot be optimised
--   away (EXPLAIN shows a full sort regardless of index or partition choice).
-- =====================================================================
USE loan_portfolio;

-- ---------------------------------------------------------------------
-- 0. The reduction
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS bureau_balance;
DROP VIEW  IF EXISTS v_bureau_balance;


-- ---------------------------------------------------------------------
-- 1. mart_roll_rate  - the 275.7s computation, run ONCE
--
-- CRITICAL: consecutive ROWS are not consecutive MONTHS. Gaps exist in the
-- panel. A transition is only counted when MONTHS_BALANCE actually advances
-- by exactly 1; otherwise we would invent transitions across missing months.
-- The number of pairs rejected for this reason is reported below.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart_roll_rate;
CREATE TABLE mart_roll_rate AS
WITH seq AS (
    SELECT PRODUCT, SK_ID_PREV, MONTHS_BALANCE, BUCKET_ANALYTICAL,
           LAG(BUCKET_ANALYTICAL) OVER (PARTITION BY SK_ID_PREV, PRODUCT
                                        ORDER BY MONTHS_BALANCE) AS from_bucket,
           LAG(MONTHS_BALANCE)    OVER (PARTITION BY SK_ID_PREV, PRODUCT
                                        ORDER BY MONTHS_BALANCE) AS prev_mb
    FROM stg_account_month
)
SELECT PRODUCT,
       from_bucket,
       BUCKET_ANALYTICAL AS to_bucket,
       COUNT(*)          AS transitions
FROM seq
WHERE from_bucket IS NOT NULL
  AND MONTHS_BALANCE = prev_mb + 1          -- consecutive months only
GROUP BY PRODUCT, from_bucket, BUCKET_ANALYTICAL;

ALTER TABLE mart_roll_rate ADD PRIMARY KEY (PRODUCT, from_bucket, to_bucket);

-- How many adjacent row-pairs were rejected because the months were not
-- consecutive?  This number belongs in the limitations register.
DROP TABLE IF EXISTS mart_roll_rate_coverage;
CREATE TABLE mart_roll_rate_coverage AS
WITH seq AS (
    SELECT PRODUCT, MONTHS_BALANCE,
           LAG(MONTHS_BALANCE) OVER (PARTITION BY SK_ID_PREV, PRODUCT
                                     ORDER BY MONTHS_BALANCE) AS prev_mb
    FROM stg_account_month
)
SELECT PRODUCT,
       COUNT(*)                                          AS adjacent_pairs,
       SUM(MONTHS_BALANCE = prev_mb + 1)                 AS consecutive_pairs,
       SUM(MONTHS_BALANCE <> prev_mb + 1)                AS gap_pairs,
       ROUND(100.0*SUM(MONTHS_BALANCE <> prev_mb + 1)/COUNT(*), 4) AS pct_gaps
FROM seq WHERE prev_mb IS NOT NULL
GROUP BY PRODUCT;


-- ---------------------------------------------------------------------
-- 2. mart_account  - one row per account, snapshot + full history summary
--    ~1,040,632 rows.  Replaces every future scan of the 13.8M panel.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart_account;
CREATE TABLE mart_account AS
SELECT
    b.PRODUCT, b.SK_ID_PREV, b.SK_ID_CURR,
    -- state at the latest observed month (the "book")
    b.MONTHS_BALANCE      AS LAST_MONTH,
    b.MOB                 AS MOB_AT_LAST,
    b.CONTRACT_STATUS,
    b.IS_ACTIVE,
    b.SK_DPD              AS DPD_NOW,
    b.SK_DPD_DEF          AS DPD_DEF_NOW,
    b.BUCKET_REPORTING,
    b.BUCKET_ANALYTICAL,
    b.EXPOSURE,
    b.EXPOSURE_IS_PROXY,
    b.UTILISATION,
    -- history summary over the whole panel
    h.MONTHS_OBSERVED,
    h.MAX_DPD_EVER,
    h.MONTHS_DELINQUENT,
    h.MONTHS_30PLUS,
    h.MONTHS_90PLUS,
    h.AVG_UTILISATION,
    h.MAX_UTILISATION,
    -- deterioration: DPD in the last 3 observed months vs the 3 before that
    h.DPD_RECENT3,
    h.DPD_PRIOR3,
    CASE WHEN h.DPD_RECENT3 > h.DPD_PRIOR3 THEN 1 ELSE 0 END AS IS_DETERIORATING
FROM stg_book b
JOIN (
    SELECT SK_ID_PREV, PRODUCT,
           COUNT(*)                                   AS MONTHS_OBSERVED,
           MAX(SK_DPD)                                AS MAX_DPD_EVER,
           SUM(SK_DPD > 0)                            AS MONTHS_DELINQUENT,
           SUM(SK_DPD > 30)                           AS MONTHS_30PLUS,
           SUM(SK_DPD > 90)                           AS MONTHS_90PLUS,
           ROUND(AVG(UTILISATION), 4)                 AS AVG_UTILISATION,
           ROUND(MAX(UTILISATION), 4)                 AS MAX_UTILISATION,
           MAX(CASE WHEN rn <= 3 THEN SK_DPD END)     AS DPD_RECENT3,
           MAX(CASE WHEN rn BETWEEN 4 AND 6 THEN SK_DPD END) AS DPD_PRIOR3
    FROM (SELECT SK_ID_PREV, PRODUCT, SK_DPD, UTILISATION,
                 ROW_NUMBER() OVER (PARTITION BY SK_ID_PREV, PRODUCT
                                    ORDER BY MONTHS_BALANCE DESC) AS rn
          FROM stg_account_month) x
    GROUP BY SK_ID_PREV, PRODUCT
) h ON h.SK_ID_PREV = b.SK_ID_PREV AND h.PRODUCT = b.PRODUCT;

ALTER TABLE mart_account
  ADD PRIMARY KEY (SK_ID_PREV, PRODUCT),
  ADD INDEX ix_ma_curr (SK_ID_CURR),
  ADD INDEX ix_ma_live (IS_ACTIVE, BUCKET_ANALYTICAL);


-- ---------------------------------------------------------------------
-- 3. mart_customer  - one row per customer, 356,255 rows.
--    Joins application attributes to behavioural aggregates. This is the
--    table the early-warning module (M10/M11) is built on.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart_customer;
CREATE TABLE mart_customer AS
SELECT
    a.SK_ID_CURR, a.SOURCE, a.TARGET,
    a.CODE_GENDER, a.AGE_YEARS, a.NAME_INCOME_TYPE, a.NAME_EDUCATION_TYPE,
    a.NAME_FAMILY_STATUS, a.OCCUPATION_TYPE, a.ORGANIZATION_TYPE,
    a.AMT_INCOME_TOTAL, a.AMT_CREDIT, a.AMT_ANNUITY,
    a.FLAG_NOT_EMPLOYED, a.EMPLOYMENT_YEARS,
    a.EXT_SOURCE_1, a.EXT_SOURCE_2, a.EXT_SOURCE_3,
    a.FLAG_EXT_SOURCE_1_MISSING, a.FLAG_EXT_SOURCE_3_MISSING,
    a.REGION_RATING_CLIENT,
    a.AMT_REQ_CREDIT_BUREAU_YEAR, a.AMT_REQ_CREDIT_BUREAU_QRT,
    -- internal account behaviour
    COALESCE(acc.N_ACCOUNTS, 0)            AS N_ACCOUNTS,
    COALESCE(acc.N_ACTIVE, 0)              AS N_ACTIVE_ACCOUNTS,
    acc.TOTAL_EXPOSURE,
    COALESCE(acc.MAX_DPD_NOW, 0)           AS MAX_DPD_NOW,
    COALESCE(acc.MAX_DPD_EVER, 0)          AS MAX_DPD_EVER,
    COALESCE(acc.MONTHS_DELINQUENT, 0)     AS MONTHS_DELINQUENT,
    COALESCE(acc.N_DETERIORATING, 0)       AS N_DETERIORATING_ACCOUNTS,
    acc.MAX_UTILISATION,
    -- installment repayment behaviour  ([D4] uses settlement-based lateness)
    ins.N_INSTALMENTS, ins.N_LATE, ins.PCT_LATE,
    ins.N_LATE_30PLUS, ins.AVG_DAYS_LATE, ins.MAX_DAYS_LATE,
    ins.N_SHORTFALL, ins.TOTAL_SHORTFALL,
    -- external bureau summary (bureau kept; bureau_balance dropped)
    COALESCE(bur.N_BUREAU_CREDITS, 0)      AS N_BUREAU_CREDITS,
    COALESCE(bur.N_BUREAU_ACTIVE, 0)       AS N_BUREAU_ACTIVE,
    COALESCE(bur.N_BUREAU_OVERDUE, 0)      AS N_BUREAU_OVERDUE,
    bur.MAX_BUREAU_OVERDUE_DAYS,
    bur.TOTAL_BUREAU_DEBT
FROM v_application a
LEFT JOIN (
    SELECT SK_ID_CURR,
           COUNT(*)                                AS N_ACCOUNTS,
           SUM(IS_ACTIVE)                          AS N_ACTIVE,
           SUM(CASE WHEN IS_ACTIVE=1 THEN EXPOSURE END) AS TOTAL_EXPOSURE,
           MAX(CASE WHEN IS_ACTIVE=1 THEN DPD_NOW END)  AS MAX_DPD_NOW,
           MAX(MAX_DPD_EVER)                       AS MAX_DPD_EVER,
           SUM(MONTHS_DELINQUENT)                  AS MONTHS_DELINQUENT,
           SUM(IS_DETERIORATING)                   AS N_DETERIORATING,
           MAX(MAX_UTILISATION)                    AS MAX_UTILISATION
    FROM mart_account GROUP BY SK_ID_CURR
) acc ON acc.SK_ID_CURR = a.SK_ID_CURR
LEFT JOIN (
    SELECT SK_ID_CURR,
           COUNT(*)                                     AS N_INSTALMENTS,
           SUM(DAYS_LATE_SETTLED > 0)                   AS N_LATE,
           ROUND(100.0*SUM(DAYS_LATE_SETTLED > 0)/COUNT(*), 3) AS PCT_LATE,
           SUM(DAYS_LATE_SETTLED > 30)                  AS N_LATE_30PLUS,
           ROUND(AVG(DAYS_LATE_SETTLED), 2)             AS AVG_DAYS_LATE,
           MAX(DAYS_LATE_SETTLED)                       AS MAX_DAYS_LATE,
           SUM(SHORTFALL > 0.01)                        AS N_SHORTFALL,
           ROUND(SUM(GREATEST(SHORTFALL, 0)), 2)        AS TOTAL_SHORTFALL
    FROM stg_installment GROUP BY SK_ID_CURR
) ins ON ins.SK_ID_CURR = a.SK_ID_CURR
LEFT JOIN (
    SELECT SK_ID_CURR,
           COUNT(*)                                          AS N_BUREAU_CREDITS,
           SUM(CREDIT_ACTIVE = 'Active')                     AS N_BUREAU_ACTIVE,
           SUM(CREDIT_DAY_OVERDUE > 0)                       AS N_BUREAU_OVERDUE,
           MAX(CREDIT_DAY_OVERDUE)                           AS MAX_BUREAU_OVERDUE_DAYS,
           ROUND(SUM(GREATEST(AMT_CREDIT_SUM_DEBT, 0)), 2)   AS TOTAL_BUREAU_DEBT
    FROM bureau GROUP BY SK_ID_CURR
) bur ON bur.SK_ID_CURR = a.SK_ID_CURR;

ALTER TABLE mart_customer
  ADD PRIMARY KEY (SK_ID_CURR),
  ADD INDEX ix_mc_target (SOURCE, TARGET);


-- ---------------------------------------------------------------------
-- 4. mart_collections_queue - the delinquent live book. ~7,211 rows.
--    Small enough to inspect row by row, which is the point.
--    Scoring rule is deliberately transparent and is NOT a predictive model.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart_collections_queue;
CREATE TABLE mart_collections_queue AS
SELECT
    ma.SK_ID_PREV, ma.PRODUCT, ma.SK_ID_CURR,
    ma.DPD_NOW, ma.DPD_DEF_NOW, ma.BUCKET_REPORTING,
    ma.EXPOSURE, ma.EXPOSURE_IS_PROXY, ma.UTILISATION,
    ma.MONTHS_DELINQUENT, ma.MAX_DPD_EVER, ma.IS_DETERIORATING,
    mc.AGE_YEARS, mc.NAME_INCOME_TYPE, mc.AMT_INCOME_TOTAL,
    mc.PCT_LATE, mc.N_LATE_30PLUS, mc.N_BUREAU_OVERDUE,
    -- materiality: still delinquent once trivial balances are ignored?  [D3]
    CASE WHEN ma.DPD_DEF_NOW > 0 THEN 1 ELSE 0 END AS IS_MATERIAL
FROM mart_account ma
JOIN mart_customer mc ON mc.SK_ID_CURR = ma.SK_ID_CURR
WHERE ma.IS_ACTIVE = 1 AND ma.DPD_NOW > 0;

ALTER TABLE mart_collections_queue ADD PRIMARY KEY (SK_ID_PREV, PRODUCT);

ANALYZE TABLE mart_account, mart_customer, mart_collections_queue, mart_roll_rate;

-- ---------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------
SELECT 'mart_account'           AS tbl, COUNT(*) AS rows_built FROM mart_account
UNION ALL SELECT 'mart_customer',        COUNT(*) FROM mart_customer
UNION ALL SELECT 'mart_collections_queue',COUNT(*) FROM mart_collections_queue
UNION ALL SELECT 'mart_roll_rate',       COUNT(*) FROM mart_roll_rate;

SELECT * FROM mart_roll_rate_coverage;

SELECT ROUND(SUM(DATA_LENGTH+INDEX_LENGTH)/1024/1024/1024, 2) AS db_size_gb
FROM information_schema.TABLES WHERE TABLE_SCHEMA='loan_portfolio';
