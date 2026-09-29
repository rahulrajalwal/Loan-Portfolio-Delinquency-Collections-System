-- =====================================================================
-- PHASE 9 - EARLY-WARNING SIGNAL EVALUATION   (modules M10, M11)
--
-- This is an ANALYTICAL RISK PRIORITISATION FRAMEWORK, not a bank risk model
-- and not a predictive model. Every rule is a plain, inspectable condition.
--
-- Method:
--   E1  measure each candidate signal ALONE against the observed outcome
--   E2  test whether signals are independent or just the same signal twice
--   E3  combine into a transparent additive count
--   E4  precision / recall / lift at every threshold
--   E5  check the framework is stable across segments
--
-- Benchmark: TARGET = 8.0729% over 307,511 train customers (24,825 defaults).
-- Every rate below is published with its denominator.
-- =====================================================================
USE loan_portfolio;

SELECT '======== E1  INDIVIDUAL SIGNAL PERFORMANCE ========' AS section;
-- For each signal:
--   flagged      how many customers it fires on      (operational load)
--   target_pct   observed default rate among flagged (precision)
--   lift         vs the 8.0729% base rate
--   recall_pct   share of ALL defaults it catches    (coverage)
-- A signal is only useful if lift is meaningful AND recall is non-trivial.
WITH base AS (SELECT COUNT(*) n, SUM(TARGET) d FROM mart_customer WHERE SOURCE='train'),
sig AS (
    SELECT 'S1 ever 30+ days late (first-payment defn)' AS signal_name,
           COUNT(*) AS flagged, SUM(TARGET) AS defaults
    FROM mart_customer WHERE SOURCE='train' AND N_LATE_FIRST_30PLUS > 0
    UNION ALL SELECT 'S2 any installment shortfall', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND N_SHORTFALL > 0
    UNION ALL SELECT 'S3 external bureau credit overdue', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND N_BUREAU_OVERDUE > 0
    UNION ALL SELECT 'S4 any account ever delinquent', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND MAX_DPD_EVER > 0
    UNION ALL SELECT 'S5 account currently deteriorating', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND N_DETERIORATING_ACCOUNTS > 0
    UNION ALL SELECT 'S6 EXT_SOURCE_3 missing', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND FLAG_EXT_SOURCE_3_MISSING = 1
    UNION ALL SELECT 'S7 EXT_SOURCE_1 missing', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND FLAG_EXT_SOURCE_1_MISSING = 1
    UNION ALL SELECT 'S8 2+ bureau enquiries in the quarter', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND AMT_REQ_CREDIT_BUREAU_QRT >= 2
    UNION ALL SELECT 'S9 card ever over limit', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND MAX_UTILISATION > 1.0
    UNION ALL SELECT 'S10 currently delinquent (live book)', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND MAX_DPD_NOW > 0
    UNION ALL SELECT 'S11 delinquent 3+ months in history', COUNT(*), SUM(TARGET)
    FROM mart_customer WHERE SOURCE='train' AND MONTHS_DELINQUENT >= 3
)
SELECT s.signal_name, s.flagged,
       ROUND(100.0*s.flagged/b.n, 2)                  AS pct_of_book,
       s.defaults,
       ROUND(100.0*s.defaults/s.flagged, 3)           AS target_pct,
       ROUND((s.defaults/s.flagged)/(b.d/b.n), 2)     AS lift,
       ROUND(100.0*s.defaults/b.d, 2)                 AS recall_pct
FROM sig s CROSS JOIN base b
ORDER BY lift DESC;


SELECT '======== E2  ARE THE SIGNALS INDEPENDENT? ========' AS section;
-- WHY  If two signals fire on the same customers, adding both to a score
--      double-counts one piece of evidence. This measures the overlap.
-- Read: of customers flagged by A, what share are also flagged by B?
SELECT
  ROUND(100.0*AVG(CASE WHEN s1=1 THEN s2 END), 1) AS pct_of_S1_also_S2,
  ROUND(100.0*AVG(CASE WHEN s1=1 THEN s3 END), 1) AS pct_of_S1_also_S3,
  ROUND(100.0*AVG(CASE WHEN s2=1 THEN s3 END), 1) AS pct_of_S2_also_S3,
  ROUND(100.0*AVG(CASE WHEN s1=1 THEN s5 END), 1) AS pct_of_S1_also_S5,
  ROUND(100.0*AVG(CASE WHEN s3=1 THEN s6 END), 1) AS pct_of_S3_also_S6,
  ROUND(100.0*AVG(s1),1) AS pct_S1, ROUND(100.0*AVG(s2),1) AS pct_S2,
  ROUND(100.0*AVG(s3),1) AS pct_S3, ROUND(100.0*AVG(s5),1) AS pct_S5,
  ROUND(100.0*AVG(s6),1) AS pct_S6
FROM (SELECT (N_LATE_FIRST_30PLUS > 0)        AS s1,
             (N_SHORTFALL > 0)                AS s2,
             (N_BUREAU_OVERDUE > 0)           AS s3,
             (N_DETERIORATING_ACCOUNTS > 0)   AS s5,
             (FLAG_EXT_SOURCE_3_MISSING = 1)  AS s6
      FROM mart_customer WHERE SOURCE='train') t;


SELECT '======== E3  THE FRAMEWORK - additive signal count ========' AS section;
-- Five signals, each worth 1 point. Deliberately unweighted: weights would
-- imply a fitted model, and this is a transparent rule set.
--   S1 ever 30+ late      - internal repayment behaviour
--   S2 shortfall          - internal payment adequacy
--   S3 bureau overdue     - external credit behaviour
--   S5 deteriorating      - momentum on the live book
--   S11 3+ months delinq  - persistence of internal delinquency
SELECT signal_count,
       COUNT(*)                                          AS customers,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 3)    AS pct_of_book,
       SUM(TARGET)                                       AS defaults,
       ROUND(100.0*AVG(TARGET), 3)                       AS target_pct,
       ROUND(AVG(TARGET)/0.080729, 2)                    AS lift
FROM (SELECT TARGET,
             (N_LATE_FIRST_30PLUS > 0) + (N_SHORTFALL > 0) + (N_BUREAU_OVERDUE > 0)
           + (N_DETERIORATING_ACCOUNTS > 0) + (MONTHS_DELINQUENT >= 3) AS signal_count
      FROM mart_customer WHERE SOURCE='train') t
GROUP BY signal_count ORDER BY signal_count;


SELECT '======== E4  THRESHOLD TRADE-OFF (precision vs recall) ========' AS section;
-- The operational question: where do you draw the line?
-- Flag too few and you miss defaults; flag too many and you waste capacity.
WITH scored AS (
    SELECT TARGET,
           (N_LATE_FIRST_30PLUS > 0) + (N_SHORTFALL > 0) + (N_BUREAU_OVERDUE > 0)
         + (N_DETERIORATING_ACCOUNTS > 0) + (MONTHS_DELINQUENT >= 3) AS sc
    FROM mart_customer WHERE SOURCE='train'
), tot AS (SELECT COUNT(*) n, SUM(TARGET) d FROM scored)
SELECT th AS threshold_at_least,
       SUM(sc >= th)                                                 AS flagged,
       ROUND(100.0*SUM(sc >= th)/MAX(tot.n), 3)                      AS pct_book_flagged,
       SUM(CASE WHEN sc >= th THEN TARGET ELSE 0 END)                AS defaults_caught,
       ROUND(100.0*SUM(CASE WHEN sc >= th THEN TARGET ELSE 0 END)
             / NULLIF(SUM(sc >= th),0), 3)                           AS precision_pct,
       ROUND(100.0*SUM(CASE WHEN sc >= th THEN TARGET ELSE 0 END)/MAX(tot.d), 3) AS recall_pct,
       ROUND((SUM(CASE WHEN sc >= th THEN TARGET ELSE 0 END)/NULLIF(SUM(sc >= th),0))
             / 0.080729, 2)                                          AS lift
FROM scored CROSS JOIN tot
CROSS JOIN (SELECT 1 AS th UNION SELECT 2 UNION SELECT 3 UNION SELECT 4 UNION SELECT 5) thr
GROUP BY th ORDER BY th;


SELECT '======== E5  IS THE FRAMEWORK STABLE ACROSS SEGMENTS? ========' AS section;
-- WHY  A score that only works for one group is not a framework, it is an
--      artefact. If the gradient holds everywhere, the rules are carrying
--      real behavioural information rather than proxying for demographics.
SELECT NAME_INCOME_TYPE,
       COUNT(*)                                                        AS customers,
       ROUND(100.0*AVG(CASE WHEN sc = 0 THEN TARGET END), 3)           AS target_score0,
       ROUND(100.0*AVG(CASE WHEN sc = 1 THEN TARGET END), 3)           AS target_score1,
       ROUND(100.0*AVG(CASE WHEN sc >= 2 THEN TARGET END), 3)          AS target_score2plus,
       SUM(sc >= 2)                                                    AS n_score2plus
FROM (SELECT NAME_INCOME_TYPE, TARGET,
             (N_LATE_FIRST_30PLUS > 0) + (N_SHORTFALL > 0) + (N_BUREAU_OVERDUE > 0)
           + (N_DETERIORATING_ACCOUNTS > 0) + (MONTHS_DELINQUENT >= 3) AS sc
      FROM mart_customer WHERE SOURCE='train') t
GROUP BY NAME_INCOME_TYPE HAVING customers >= 1000
ORDER BY customers DESC;

-- Same test across age bands - demographics were FLAT on delinquency in Phase 6,
-- so if the score gradient holds here too, it is behaviour and not age.
SELECT CASE WHEN AGE_YEARS < 30 THEN 'under 30' WHEN AGE_YEARS < 40 THEN '30-39'
            WHEN AGE_YEARS < 50 THEN '40-49'    WHEN AGE_YEARS < 60 THEN '50-59'
            ELSE '60+' END                                             AS age_band,
       COUNT(*)                                                        AS customers,
       ROUND(100.0*AVG(CASE WHEN sc = 0 THEN TARGET END), 3)           AS target_score0,
       ROUND(100.0*AVG(CASE WHEN sc >= 2 THEN TARGET END), 3)          AS target_score2plus,
       SUM(sc >= 2)                                                    AS n_score2plus
FROM (SELECT AGE_YEARS, TARGET,
             (N_LATE_FIRST_30PLUS > 0) + (N_SHORTFALL > 0) + (N_BUREAU_OVERDUE > 0)
           + (N_DETERIORATING_ACCOUNTS > 0) + (MONTHS_DELINQUENT >= 3) AS sc
      FROM mart_customer WHERE SOURCE='train') t
GROUP BY age_band ORDER BY age_band;
