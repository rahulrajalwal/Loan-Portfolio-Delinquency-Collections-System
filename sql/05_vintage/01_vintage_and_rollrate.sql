-- =====================================================================
-- PHASE 8 - VINTAGE, COHORT & ROLL-RATE   (modules M7, M8, M9)
--
-- TIME IN THIS DATASET
-- --------------------
-- There are no calendar dates. Two consequences, stated wherever used:
--   1. Cohorts are ORIGINATION-RECENCY BANDS ("decided 0-12 months before the
--      customer's new application"), not calendar quarters.
--   2. MOB is months since the account's FIRST OBSERVED month in the panel.
--      V1 tests how well that approximates true months-on-book.
--
-- Roll rates come from mart_roll_rate, pre-computed once (275.7s) with a
-- consecutive-month guard so no transition is invented across a gap.
-- =====================================================================
USE loan_portfolio;

-- ---------------------------------------------------------------------
-- V0 - build mart_vintage.  One pass over the 13.8M panel, run once.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS mart_vintage;
CREATE TABLE mart_vintage AS
SELECT
    CASE WHEN pa.DAYS_DECISION >= -365  THEN '1: 0-12m before app'
         WHEN pa.DAYS_DECISION >= -730  THEN '2: 13-24m'
         WHEN pa.DAYS_DECISION >= -1095 THEN '3: 25-36m'
         WHEN pa.DAYS_DECISION >= -1460 THEN '4: 37-48m'
         ELSE                                '5: 48m+' END      AS cohort,
    am.PRODUCT,
    am.MOB,
    COUNT(*)                            AS account_months,
    COUNT(DISTINCT am.SK_ID_PREV)       AS accounts,
    SUM(am.SK_DPD > 0)                  AS delinquent,
    SUM(am.SK_DPD > 30)                 AS delinq_30plus,
    SUM(am.SK_DPD > 90)                 AS delinq_90plus
FROM stg_account_month am
JOIN previous_application pa ON pa.SK_ID_PREV = am.SK_ID_PREV
WHERE pa.DAYS_DECISION IS NOT NULL
GROUP BY cohort, am.PRODUCT, am.MOB;

ALTER TABLE mart_vintage ADD PRIMARY KEY (cohort, PRODUCT, MOB);


SELECT '======== V1  IS OBSERVED MOB A FAIR PROXY FOR TRUE AGE? ========' AS section;
-- WHAT  Compare the account's first observed month against its decision date.
-- WHY   If the panel starts well after origination, MOB understates true age and
--       every vintage curve is shifted left. This must be measured, not assumed.
-- Expect: for accounts decided long ago, the panel window truncates the history.
SELECT CASE WHEN pa.DAYS_DECISION >= -365  THEN '1: 0-12m before app'
            WHEN pa.DAYS_DECISION >= -730  THEN '2: 13-24m'
            WHEN pa.DAYS_DECISION >= -1095 THEN '3: 25-36m'
            WHEN pa.DAYS_DECISION >= -1460 THEN '4: 37-48m'
            ELSE                                '5: 48m+' END       AS cohort,
       COUNT(*)                                                     AS accounts,
       ROUND(AVG(-pa.DAYS_DECISION/30.44), 1)                       AS avg_true_age_months,
       ROUND(AVG(f.first_month * -1), 1)                            AS avg_panel_start_months_ago,
       ROUND(AVG(f.months_seen), 1)                                 AS avg_months_observed,
       ROUND(AVG(-pa.DAYS_DECISION/30.44) - AVG(f.months_seen), 1)  AS avg_history_missing
FROM previous_application pa
JOIN (SELECT SK_ID_PREV, MIN(MONTHS_BALANCE) AS first_month, COUNT(*) AS months_seen
      FROM stg_account_month GROUP BY SK_ID_PREV) f ON f.SK_ID_PREV = pa.SK_ID_PREV
WHERE pa.DAYS_DECISION IS NOT NULL
GROUP BY cohort ORDER BY cohort;


SELECT '======== V2  VINTAGE CURVES - delinquency by months on book ========' AS section;
-- WHAT  Delinquency rate at each MOB, by origination-recency cohort.
-- WHY   Cohorts must be compared at EQUAL AGE. Comparing a young cohort's
--       delinquency to an old one's is meaningless - loans need time to go bad.
-- Counts published so thin cells are visible.
SELECT cohort, MOB,
       SUM(accounts)                                              AS accounts,
       SUM(account_months)                                        AS account_months,
       ROUND(100.0*SUM(delinquent)/SUM(account_months), 3)        AS delinq_pct,
       ROUND(100.0*SUM(delinq_30plus)/SUM(account_months), 3)     AS delinq_30plus_pct
FROM mart_vintage
WHERE MOB <= 24
GROUP BY cohort, MOB
HAVING account_months >= 500          -- suppress cells too thin to read
ORDER BY cohort, MOB;


SELECT '======== V3  ROLL-RATE MATRIX (pre-computed) ========' AS section;
-- WHAT  P(bucket next month | bucket this month), per product.
-- WHY   Momentum. Two books with identical delinquency can have completely
--       different futures. Every cell carries its transition COUNT, because
--       Phase 5 showed the middle buckets are thinly populated.
SELECT PRODUCT,
       from_bucket,
       to_bucket,
       transitions,
       SUM(transitions) OVER (PARTITION BY PRODUCT, from_bucket)  AS from_total,
       ROUND(100.0*transitions
             / SUM(transitions) OVER (PARTITION BY PRODUCT, from_bucket), 3) AS roll_pct
FROM mart_roll_rate
ORDER BY PRODUCT, from_bucket, to_bucket;


SELECT '======== V4  CURE vs FORWARD ROLL ========' AS section;
-- WHAT  Collapse the matrix into the three things a risk manager actually asks:
--       did it get better, stay put, or get worse?
-- WHY   This is the headline momentum measure.
WITH ord AS (
    SELECT PRODUCT, from_bucket, to_bucket, transitions,
           FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+') AS f_ord,
           FIELD(to_bucket,  '0-current','1-30','31-90','91-360','360+') AS t_ord
    FROM mart_roll_rate
)
SELECT PRODUCT, from_bucket,
       SUM(transitions)                                              AS total_transitions,
       ROUND(100.0*SUM(CASE WHEN t_ord < f_ord THEN transitions END)/SUM(transitions),3) AS cure_pct,
       ROUND(100.0*SUM(CASE WHEN t_ord = f_ord THEN transitions END)/SUM(transitions),3) AS stay_pct,
       ROUND(100.0*SUM(CASE WHEN t_ord > f_ord THEN transitions END)/SUM(transitions),3) AS forward_roll_pct
FROM ord
GROUP BY PRODUCT, from_bucket
ORDER BY PRODUCT, FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+');


SELECT '======== V5  NPA FORMATION CHAIN ========' AS section;
-- WHAT  Chain the forward-roll rates to estimate how many of today's 1-30
--       accounts would reach 91-360, if these rates persisted.
-- WHY   This is how lenders forecast future NPA formation from today's early
--       buckets (concept A6).
-- CAUTION: this is a STEADY-STATE illustration, not a forecast. It assumes the
--          observed transition rates hold and ignores new accounts entering.
WITH ord AS (
    SELECT PRODUCT, from_bucket, to_bucket, transitions,
           FIELD(from_bucket,'0-current','1-30','31-90','91-360','360+') AS f_ord,
           FIELD(to_bucket,  '0-current','1-30','31-90','91-360','360+') AS t_ord
    FROM mart_roll_rate
),
fwd AS (
    SELECT PRODUCT, from_bucket,
           SUM(CASE WHEN t_ord > f_ord THEN transitions ELSE 0 END)/SUM(transitions) AS p_forward,
           SUM(transitions) AS n
    FROM ord GROUP BY PRODUCT, from_bucket
)
SELECT a.PRODUCT,
       ROUND(100.0*a.p_forward, 3)                       AS pct_1_30_rolls_forward,
       a.n                                               AS n_from_1_30,
       ROUND(100.0*b.p_forward, 3)                       AS pct_31_90_rolls_forward,
       b.n                                               AS n_from_31_90,
       ROUND(100.0*a.p_forward*b.p_forward, 4)           AS pct_1_30_reaching_91_360,
       ROUND(1000*a.p_forward*b.p_forward, 1)            AS per_1000_accounts
FROM fwd a JOIN fwd b ON b.PRODUCT = a.PRODUCT AND b.from_bucket = '31-90'
WHERE a.from_bucket = '1-30';


SELECT '======== V6  COHORT QUALITY AT EQUAL AGE (MOB 6 and 12) ========' AS section;
-- WHAT  The vintage question in one table: at the same age, are recent cohorts
--       performing worse than older ones?
-- WHY   That is the underwriting-drift signal, visible long before the headline
--       portfolio number moves.
SELECT cohort,
       MAX(CASE WHEN MOB = 6  THEN accounts END)      AS accounts_at_mob6,
       MAX(CASE WHEN MOB = 6  THEN delinq_pct END)    AS delinq_pct_mob6,
       MAX(CASE WHEN MOB = 12 THEN accounts END)      AS accounts_at_mob12,
       MAX(CASE WHEN MOB = 12 THEN delinq_pct END)    AS delinq_pct_mob12,
       MAX(CASE WHEN MOB = 18 THEN delinq_pct END)    AS delinq_pct_mob18
FROM (SELECT cohort, MOB, SUM(accounts) AS accounts,
             ROUND(100.0*SUM(delinquent)/SUM(account_months), 3) AS delinq_pct
      FROM mart_vintage GROUP BY cohort, MOB) t
WHERE MOB IN (6, 12, 18)
GROUP BY cohort ORDER BY cohort;
