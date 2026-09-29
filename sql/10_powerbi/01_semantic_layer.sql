-- =====================================================================
-- PHASE 12 - POWER BI SEMANTIC LAYER
--
-- A deliberate star schema rather than one flat export:
--
--        pbi_customer  (dimension, 356,255)
--             |  1
--             |
--             |  *                    *              *
--        pbi_account  ---------  pbi_queue      (drill-through)
--       (fact, 1,040,632)        (fact, 7,211)
--
--        pbi_rollrate (40)   pbi_vintage   pbi_signal  -- small standalone facts
--
-- WHY a star and not one wide table:
--   * a wide table repeats every customer attribute on every account row -
--     the same fan-out error the whole project has been guarding against
--   * Power BI's engine is built for star schemas; filters propagate
--     dimension -> fact along the relationship
--   * customer counts stay correct. On a flat table, DISTINCTCOUNT is needed
--     everywhere and a plain COUNT silently over-counts.
--
-- Every field below traces to a measured number. No metric appears here that
-- the data cannot support.
-- =====================================================================
USE loan_portfolio;

-- ---------------------------------------------------------------------
-- DIMENSION: customer
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS pbi_customer;
CREATE VIEW pbi_customer AS
SELECT
    SK_ID_CURR,
    SOURCE                                            AS data_source,
    TARGET                                            AS had_payment_difficulty,
    CODE_GENDER                                       AS gender,
    NAME_INCOME_TYPE                                  AS income_type,
    NAME_EDUCATION_TYPE                               AS education,
    NAME_FAMILY_STATUS                                AS family_status,
    OCCUPATION_TYPE                                   AS occupation,
    REGION_RATING_CLIENT                              AS region_rating,
    AGE_YEARS                                         AS age_years,
    CASE WHEN AGE_YEARS < 30 THEN '1: under 30' WHEN AGE_YEARS < 40 THEN '2: 30-39'
         WHEN AGE_YEARS < 50 THEN '3: 40-49'    WHEN AGE_YEARS < 60 THEN '4: 50-59'
         ELSE '5: 60+' END                            AS age_band,
    FLAG_NOT_EMPLOYED                                 AS is_not_employed,
    AMT_INCOME_TOTAL                                  AS income,
    AMT_CREDIT                                        AS credit_applied,
    -- behavioural signals (Phase 9)
    COALESCE(N_LATE_FIRST_30PLUS,0) > 0               AS sig_ever_30plus_late,
    COALESCE(N_SHORTFALL,0)        > 0                AS sig_shortfall,
    COALESCE(N_BUREAU_OVERDUE,0)   > 0                AS sig_bureau_overdue,
    COALESCE(N_DETERIORATING_ACCOUNTS,0) > 0          AS sig_deteriorating,
    COALESCE(MONTHS_DELINQUENT,0) >= 3                AS sig_chronic_delinquency,
    (COALESCE(N_LATE_FIRST_30PLUS,0) > 0) + (COALESCE(N_SHORTFALL,0) > 0)
  + (COALESCE(N_BUREAU_OVERDUE,0) > 0) + (COALESCE(N_DETERIORATING_ACCOUNTS,0) > 0)
  + (COALESCE(MONTHS_DELINQUENT,0) >= 3)             AS signal_count,
    PCT_LATE_FIRST                                    AS pct_installments_late,
    N_BUREAU_CREDITS                                  AS n_external_credits
FROM mart_customer;

-- ---------------------------------------------------------------------
-- FACT: account (the book).  One row per account at its latest observed month.
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS pbi_account;
CREATE VIEW pbi_account AS
SELECT
    SK_ID_PREV                                        AS account_id,
    SK_ID_CURR,
    PRODUCT                                           AS product,
    CONTRACT_STATUS                                   AS contract_status,
    IS_ACTIVE                                         AS is_active,
    DPD_NOW                                           AS dpd,
    BUCKET_REPORTING                                  AS bucket_reporting,
    BUCKET_ANALYTICAL                                 AS bucket_analytical,
    EXPOSURE                                          AS exposure,
    EXPOSURE_IS_PROXY                                 AS exposure_is_proxy,
    UTILISATION                                       AS utilisation,
    CASE WHEN UTILISATION IS NULL      THEN '0: not applicable'
         WHEN UTILISATION <= 0.30      THEN '1: 0-30%'
         WHEN UTILISATION <= 0.60      THEN '2: 30-60%'
         WHEN UTILISATION <= 0.90      THEN '3: 60-90%'
         WHEN UTILISATION <= 1.00      THEN '4: 90-100%'
         ELSE                               '5: over limit' END AS utilisation_band,
    MONTHS_OBSERVED                                   AS months_observed,
    MOB_AT_LAST                                       AS months_on_book,
    MAX_DPD_EVER                                      AS max_dpd_ever,
    MONTHS_DELINQUENT                                 AS months_delinquent,
    IS_DETERIORATING                                  AS is_deteriorating,
    (DPD_NOW > 0)                                     AS is_delinquent,
    (DPD_DEF_NOW > 0)                                 AS is_material_delinquent
FROM mart_account;

-- ---------------------------------------------------------------------
-- FACT: collections queue (drill-through detail, 7,211 rows)
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS pbi_queue;
CREATE VIEW pbi_queue AS
SELECT
    SK_ID_PREV                                        AS account_id,
    SK_ID_CURR,
    PRODUCT                                           AS product,
    priority_tier,
    DPD_NOW                                           AS dpd,
    BUCKET_ANALYTICAL                                 AS bucket,
    EXPOSURE                                          AS exposure,
    EXPOSURE_IS_PROXY                                 AS exposure_is_proxy,
    cure_rate                                         AS observed_cure_rate,
    cure_weighted_exposure                            AS curable_value,
    IS_DETERIORATING                                  AS is_deteriorating,
    IS_MATERIAL                                       AS is_material,
    IS_CHRONIC                                        AS is_chronic,
    value_quintile
FROM mart_queue_tiered;

-- ---------------------------------------------------------------------
-- FACT: roll rate (40 rows) - momentum
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS pbi_rollrate;
CREATE VIEW pbi_rollrate AS
SELECT r.PRODUCT AS product, r.from_bucket, r.to_bucket, r.transitions,
       SUM(r.transitions) OVER (PARTITION BY r.PRODUCT, r.from_bucket) AS from_total,
       ROUND(100.0*r.transitions
             / SUM(r.transitions) OVER (PARTITION BY r.PRODUCT, r.from_bucket), 3) AS roll_pct,
       CASE WHEN FIELD(r.to_bucket,  '0-current','1-30','31-90','91-360','360+')
               < FIELD(r.from_bucket,'0-current','1-30','31-90','91-360','360+') THEN 'cure'
            WHEN FIELD(r.to_bucket,  '0-current','1-30','31-90','91-360','360+')
               = FIELD(r.from_bucket,'0-current','1-30','31-90','91-360','360+') THEN 'stay'
            ELSE 'forward roll' END AS direction
FROM mart_roll_rate r;

-- ---------------------------------------------------------------------
-- FACT: vintage curves
-- ---------------------------------------------------------------------
DROP VIEW IF EXISTS pbi_vintage;
CREATE VIEW pbi_vintage AS
SELECT cohort, PRODUCT AS product, MOB AS months_on_book,
       accounts, account_months, delinquent, delinq_30plus,
       ROUND(100.0*delinquent/NULLIF(account_months,0), 3)    AS delinq_pct,
       ROUND(100.0*delinq_30plus/NULLIF(account_months,0), 3) AS delinq_30plus_pct
FROM mart_vintage;

-- ---------------------------------------------------------------------
-- FACT: signal performance (Phase 9 E1) - a small static table so the
--       dashboard can show WHY the framework is modest, not hide it.
-- ---------------------------------------------------------------------
DROP TABLE IF EXISTS pbi_signal;
CREATE TABLE pbi_signal (
    signal_code   VARCHAR(8),
    signal_label  VARCHAR(60),
    flagged       INT,
    defaults      INT,
    target_pct    DECIMAL(8,3),
    lift          DECIMAL(6,2),
    recall_pct    DECIMAL(6,2)
);
INSERT INTO pbi_signal VALUES
 ('S3','External bureau credit overdue',      3397,  540,15.896,1.97, 2.18),
 ('S2','Any installment shortfall',           3089,  489,15.830,1.96, 1.97),
 ('S1','Ever 30+ days late',                  4558,  692,15.182,1.88, 2.79),
 ('S9','Card ever over limit',               37575, 4420,11.763,1.46,17.80),
 ('S10','Currently delinquent',               6045,  708,11.712,1.45, 2.85),
 ('S5','Account deteriorating',              30373, 3152,10.378,1.29,12.70),
 ('S4','Any account ever delinquent',        67791, 6475, 9.551,1.18,26.08),
 ('S6','EXT_SOURCE_3 missing',               60965, 5677, 9.312,1.15,22.87),
 ('S11','Delinquent 3+ months',              30820, 2813, 9.127,1.13,11.33),
 ('S7','EXT_SOURCE_1 missing',              173378,14771, 8.520,1.06,59.50),
 ('S8','2+ bureau enquiries (NO SIGNAL)',    16713, 1401, 8.383,1.04, 5.64);

-- ---------------------------------------------------------------------
-- Verification
-- ---------------------------------------------------------------------
SELECT 'pbi_customer' AS obj, COUNT(*) AS rows_exposed FROM pbi_customer
UNION ALL SELECT 'pbi_account', COUNT(*) FROM pbi_account
UNION ALL SELECT 'pbi_queue',   COUNT(*) FROM pbi_queue
UNION ALL SELECT 'pbi_rollrate',COUNT(*) FROM pbi_rollrate
UNION ALL SELECT 'pbi_vintage', COUNT(*) FROM pbi_vintage
UNION ALL SELECT 'pbi_signal',  COUNT(*) FROM pbi_signal;

-- Headline numbers the dashboard must reproduce, as a build-time check.
SELECT SUM(is_active)                                        AS live_accounts,
       ROUND(SUM(CASE WHEN is_active=1 THEN exposure END)/1000000,1) AS exposure_m,
       SUM(is_active=1 AND is_delinquent)                    AS delinquent,
       ROUND(100.0*SUM(is_active=1 AND is_delinquent)/SUM(is_active),4) AS delinq_rate_pct
FROM pbi_account;
