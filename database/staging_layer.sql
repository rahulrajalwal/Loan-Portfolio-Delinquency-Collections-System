-- =====================================================================
-- STAGING LAYER  (Phase 6)
--
-- Architecture:
--   RAW      - the 7 loaded tables. Never modified. Byte-faithful to source.
--   VIEWS    - light, row-preserving transformations (sentinel decoding, flags).
--              Cheap to evaluate, so a view is right.
--   STAGED   - materialised tables for transformations that CHANGE THE GRAIN or
--              require aggregating millions of rows. A MySQL view is not
--              materialised, so a GROUP BY over 13.6M rows would re-run on every
--              single query. These are built once, here.
--
-- Every treatment below traces to a numbered finding in docs/05_data_quality.md.
-- =====================================================================
USE loan_portfolio;

-- =====================================================================
-- 1. v_application   (Q4, Q13, Q17)
-- =====================================================================
DROP VIEW IF EXISTS v_application;
CREATE VIEW v_application AS
SELECT
    SK_ID_CURR,
    SOURCE,
    TARGET,
    NAME_CONTRACT_TYPE,
    -- Q13: placeholders become an explicit category, never silently dropped.
    CASE WHEN CODE_GENDER = 'XNA' THEN 'Unknown' ELSE CODE_GENDER END AS CODE_GENDER,
    CASE WHEN NAME_FAMILY_STATUS = 'Unknown' THEN 'Unknown' ELSE NAME_FAMILY_STATUS END AS NAME_FAMILY_STATUS,
    CASE WHEN ORGANIZATION_TYPE  = 'XNA'     THEN 'Unknown' ELSE ORGANIZATION_TYPE  END AS ORGANIZATION_TYPE,
    COALESCE(OCCUPATION_TYPE, 'Unknown')                                              AS OCCUPATION_TYPE,
    NAME_INCOME_TYPE, NAME_EDUCATION_TYPE, NAME_HOUSING_TYPE,
    AMT_INCOME_TOTAL, AMT_CREDIT, AMT_ANNUITY, AMT_GOODS_PRICE,
    CNT_CHILDREN, CNT_FAM_MEMBERS,
    REGION_RATING_CLIENT, REGION_POPULATION_RELATIVE,

    -- Q4: 365243 encodes "not currently employed" (pensioners + unemployed).
    -- Left raw it is a +1000-year tenure. The affected group defaults at 5.40%
    -- vs 8.66%, so the untreated value does not just add noise - it inverts.
    CASE WHEN DAYS_EMPLOYED = 365243 THEN NULL ELSE DAYS_EMPLOYED END        AS DAYS_EMPLOYED,
    CASE WHEN DAYS_EMPLOYED = 365243 THEN 1 ELSE 0 END                       AS FLAG_NOT_EMPLOYED,
    ROUND(-DAYS_BIRTH / 365.25, 1)                                           AS AGE_YEARS,
    CASE WHEN DAYS_EMPLOYED = 365243 THEN NULL
         ELSE ROUND(-DAYS_EMPLOYED / 365.25, 1) END                          AS EMPLOYMENT_YEARS,

    EXT_SOURCE_1, EXT_SOURCE_2, EXT_SOURCE_3,
    -- Q17: missingness is INFORMATIVE. Missing EXT_SOURCE_3 carries a 20% higher
    -- relative default rate. Never mean-fill; expose the flag as a signal instead.
    CASE WHEN EXT_SOURCE_1 IS NULL THEN 1 ELSE 0 END                         AS FLAG_EXT_SOURCE_1_MISSING,
    CASE WHEN EXT_SOURCE_3 IS NULL THEN 1 ELSE 0 END                         AS FLAG_EXT_SOURCE_3_MISSING,

    AMT_REQ_CREDIT_BUREAU_YEAR, AMT_REQ_CREDIT_BUREAU_QRT, AMT_REQ_CREDIT_BUREAU_MON,
    DEF_30_CNT_SOCIAL_CIRCLE, DEF_60_CNT_SOCIAL_CIRCLE
FROM application;


-- =====================================================================
-- 2. v_previous_application   (Q5, Q6, Q12, Q13)
-- =====================================================================
DROP VIEW IF EXISTS v_previous_application;
CREATE VIEW v_previous_application AS
SELECT
    SK_ID_PREV, SK_ID_CURR,
    NAME_CONTRACT_TYPE, NAME_CONTRACT_STATUS,
    -- Q5: only Approved contracts have a payment schedule. 633,433 non-approved
    -- rows carry NULL DAYS_* because nothing was ever disbursed - that is a FACT,
    -- not a defect. This flag is what schedule-based analysis filters on.
    CASE WHEN NAME_CONTRACT_STATUS = 'Approved' THEN 1 ELSE 0 END AS IS_APPROVED,
    AMT_APPLICATION, AMT_CREDIT, AMT_ANNUITY, AMT_DOWN_PAYMENT, AMT_GOODS_PRICE,
    CNT_PAYMENT,
    DAYS_DECISION,
    -- Q6: the same 365243 sentinel appears in five date columns (up to 55.95%).
    -- Read raw, it dates terminations ~1000 years into the future.
    CASE WHEN DAYS_FIRST_DRAWING        = 365243 THEN NULL ELSE DAYS_FIRST_DRAWING        END AS DAYS_FIRST_DRAWING,
    CASE WHEN DAYS_FIRST_DUE            = 365243 THEN NULL ELSE DAYS_FIRST_DUE            END AS DAYS_FIRST_DUE,
    CASE WHEN DAYS_LAST_DUE_1ST_VERSION = 365243 THEN NULL ELSE DAYS_LAST_DUE_1ST_VERSION END AS DAYS_LAST_DUE_1ST_VERSION,
    CASE WHEN DAYS_LAST_DUE             = 365243 THEN NULL ELSE DAYS_LAST_DUE             END AS DAYS_LAST_DUE,
    CASE WHEN DAYS_TERMINATION          = 365243 THEN NULL ELSE DAYS_TERMINATION          END AS DAYS_TERMINATION,
    -- Q13: XNA is a placeholder, not a product. Surfaced, never hidden.
    CASE WHEN NAME_PORTFOLIO    = 'XNA' THEN 'Unknown' ELSE NAME_PORTFOLIO    END AS NAME_PORTFOLIO,
    CASE WHEN NAME_PRODUCT_TYPE = 'XNA' THEN 'Unknown' ELSE NAME_PRODUCT_TYPE END AS NAME_PRODUCT_TYPE,
    CASE WHEN NAME_YIELD_GROUP  = 'XNA' THEN 'Unknown' ELSE NAME_YIELD_GROUP  END AS NAME_YIELD_GROUP,
    CHANNEL_TYPE, NAME_CLIENT_TYPE, CODE_REJECT_REASON, PRODUCT_COMBINATION
    -- Q12: NAME_CASH_LOAN_PURPOSE deliberately EXCLUDED. 95.8% of its values are
    -- XNA/XAP placeholders, so it cannot support any segment analysis.
FROM previous_application;


-- =====================================================================
-- 3. v_bureau_balance   (Q15)
-- =====================================================================
DROP VIEW IF EXISTS v_bureau_balance;
CREATE VIEW v_bureau_balance AS
SELECT
    SK_ID_BUREAU, MONTHS_BALANCE, STATUS,
    -- Q15: 'X' = unknown on 21.28% of rows. It must be excluded from BOTH the
    -- numerator and the denominator of any delinquency rate. Treating it as
    -- "current" would understate external delinquency across a fifth of history.
    CASE WHEN STATUS = 'X' THEN 0 ELSE 1 END                    AS IS_STATUS_KNOWN,
    CASE WHEN STATUS = 'C' THEN 1 ELSE 0 END                    AS IS_CLOSED,
    CASE WHEN STATUS IN ('0','1','2','3','4','5') THEN CAST(STATUS AS UNSIGNED) END AS DPD_BAND,
    CASE STATUS WHEN '0' THEN 'Current' WHEN '1' THEN '1-30'  WHEN '2' THEN '31-60'
                WHEN '3' THEN '61-90'   WHEN '4' THEN '91-120' WHEN '5' THEN '120+'
                WHEN 'C' THEN 'Closed'  WHEN 'X' THEN 'Unknown' END AS STATUS_LABEL
FROM bureau_balance;


-- =====================================================================
-- 4. stg_installment   (Q1, Q2)  -- MATERIALISED: changes the grain
--
--    RAW grain : one PAYMENT EVENT           (13,605,401 rows)
--    THIS grain: one INSTALMENT              (~12,951,918 rows)
--
--    Finding F1/Q1: 640,905 installments are settled by 2+ payments (max 12).
--    Comparing AMT_PAYMENT to AMT_INSTALMENT row-by-row flags 1,295,493 rows
--    (9.52%) as short, when 99.94% were paid in full. Aggregation is mandatory.
--
--    BOTH lateness definitions are computed here so decision [D4] can be taken
--    on measured evidence rather than preference.
-- =====================================================================
DROP TABLE IF EXISTS stg_installment;
CREATE TABLE stg_installment (
    SK_ID_PREV              INT UNSIGNED  NOT NULL,
    SK_ID_CURR              INT UNSIGNED  NOT NULL,
    NUM_INSTALMENT_VERSION  SMALLINT UNSIGNED NOT NULL,
    NUM_INSTALMENT_NUMBER   SMALLINT UNSIGNED NOT NULL,
    DAYS_INSTALMENT         SMALLINT      NULL,
    N_PAYMENTS              SMALLINT UNSIGNED NOT NULL,
    AMT_DUE                 DECIMAL(15,3) NULL,
    AMT_PAID                DECIMAL(15,3) NULL,
    SHORTFALL               DECIMAL(15,3) NULL,
    IS_FULLY_PAID           TINYINT       NOT NULL,
    IS_UNPAID               TINYINT       NOT NULL,
    DAY_FIRST_PAYMENT       SMALLINT      NULL,
    DAY_LAST_PAYMENT        SMALLINT      NULL,
    DAYS_LATE_FIRST         SMALLINT      NULL,   -- [D4] option A
    DAYS_LATE_SETTLED       SMALLINT      NULL,   -- [D4] option B
    PRIMARY KEY (SK_ID_PREV, NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER),
    KEY ix_stg_inst_curr (SK_ID_CURR)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO stg_installment
SELECT
    SK_ID_PREV, MIN(SK_ID_CURR), NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER,
    MAX(DAYS_INSTALMENT)                                            AS DAYS_INSTALMENT,
    COUNT(*)                                                        AS N_PAYMENTS,
    MAX(AMT_INSTALMENT)                                             AS AMT_DUE,
    SUM(AMT_PAYMENT)                                                AS AMT_PAID,
    MAX(AMT_INSTALMENT) - COALESCE(SUM(AMT_PAYMENT), 0)             AS SHORTFALL,
    CASE WHEN COALESCE(SUM(AMT_PAYMENT),0) >= MAX(AMT_INSTALMENT) - 0.01
         THEN 1 ELSE 0 END                                          AS IS_FULLY_PAID,
    CASE WHEN SUM(AMT_PAYMENT) IS NULL THEN 1 ELSE 0 END            AS IS_UNPAID,
    MIN(DAYS_ENTRY_PAYMENT)                                         AS DAY_FIRST_PAYMENT,
    MAX(DAYS_ENTRY_PAYMENT)                                         AS DAY_LAST_PAYMENT,
    MIN(DAYS_ENTRY_PAYMENT) - MAX(DAYS_INSTALMENT)                  AS DAYS_LATE_FIRST,
    MAX(DAYS_ENTRY_PAYMENT) - MAX(DAYS_INSTALMENT)                  AS DAYS_LATE_SETTLED
FROM installments_payments
GROUP BY SK_ID_PREV, NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER;


-- =====================================================================
-- 5. stg_account_month   -- MATERIALISED: unions two panels, derives exposure
--
--    One row = one ACCOUNT-MONTH, across POS/cash and credit-card products.
--    ~13.8M rows.
--
--    Exposure (concept A2):
--      CARD -> AMT_BALANCE                      (direct, real)
--      POS  -> CNT_INSTALMENT_FUTURE x ANNUITY  (PROXY - counts future
--              installments including interest, not principal alone)
--    EXPOSURE_IS_PROXY marks which is which so no chart can silently mix them.
--
--    Both [D2] bucket schemes are materialised side by side.
-- =====================================================================
DROP TABLE IF EXISTS stg_account_month;
CREATE TABLE stg_account_month (
    SK_ID_PREV        INT UNSIGNED  NOT NULL,
    SK_ID_CURR        INT UNSIGNED  NOT NULL,
    PRODUCT           VARCHAR(8)    NOT NULL,
    MONTHS_BALANCE    SMALLINT      NOT NULL,
    MOB               SMALLINT      NULL,
    CONTRACT_STATUS   VARCHAR(32)   NULL,
    IS_ACTIVE         TINYINT       NOT NULL,
    SK_DPD            SMALLINT UNSIGNED NOT NULL,
    SK_DPD_DEF        SMALLINT UNSIGNED NOT NULL,
    BUCKET_REPORTING  VARCHAR(12)   NOT NULL,
    BUCKET_ANALYTICAL VARCHAR(12)   NOT NULL,
    EXPOSURE          DECIMAL(15,3) NULL,
    EXPOSURE_IS_PROXY TINYINT       NOT NULL,
    UTILISATION       DECIMAL(10,4) NULL,
    PRIMARY KEY (SK_ID_PREV, PRODUCT, MONTHS_BALANCE),
    KEY ix_am_curr   (SK_ID_CURR),
    KEY ix_am_bucket (BUCKET_ANALYTICAL, MONTHS_BALANCE)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT INTO stg_account_month
SELECT p.SK_ID_PREV, p.SK_ID_CURR, 'POS', p.MONTHS_BALANCE,
       p.MONTHS_BALANCE - MIN(p.MONTHS_BALANCE) OVER (PARTITION BY p.SK_ID_PREV) AS MOB,
       p.NAME_CONTRACT_STATUS,
       CASE WHEN p.NAME_CONTRACT_STATUS = 'Active' THEN 1 ELSE 0 END,
       p.SK_DPD, p.SK_DPD_DEF,
       CASE WHEN p.SK_DPD = 0 THEN '0-current' WHEN p.SK_DPD <= 30 THEN '1-30'
            WHEN p.SK_DPD <= 60 THEN '31-60'   WHEN p.SK_DPD <= 90 THEN '61-90'
            WHEN p.SK_DPD <= 360 THEN '91-360' ELSE '360+' END,
       CASE WHEN p.SK_DPD = 0 THEN '0-current' WHEN p.SK_DPD <= 30 THEN '1-30'
            WHEN p.SK_DPD <= 90 THEN '31-90'
            WHEN p.SK_DPD <= 360 THEN '91-360' ELSE '360+' END,
       ROUND(p.CNT_INSTALMENT_FUTURE * pa.AMT_ANNUITY, 3),   -- PROXY
       1,
       NULL
FROM pos_cash_balance p
LEFT JOIN previous_application pa ON pa.SK_ID_PREV = p.SK_ID_PREV
UNION ALL
SELECT c.SK_ID_PREV, c.SK_ID_CURR, 'CARD', c.MONTHS_BALANCE,
       c.MONTHS_BALANCE - MIN(c.MONTHS_BALANCE) OVER (PARTITION BY c.SK_ID_PREV) AS MOB,
       c.NAME_CONTRACT_STATUS,
       CASE WHEN c.NAME_CONTRACT_STATUS = 'Active' THEN 1 ELSE 0 END,
       c.SK_DPD, c.SK_DPD_DEF,
       CASE WHEN c.SK_DPD = 0 THEN '0-current' WHEN c.SK_DPD <= 30 THEN '1-30'
            WHEN c.SK_DPD <= 60 THEN '31-60'   WHEN c.SK_DPD <= 90 THEN '61-90'
            WHEN c.SK_DPD <= 360 THEN '91-360' ELSE '360+' END,
       CASE WHEN c.SK_DPD = 0 THEN '0-current' WHEN c.SK_DPD <= 30 THEN '1-30'
            WHEN c.SK_DPD <= 90 THEN '31-90'
            WHEN c.SK_DPD <= 360 THEN '91-360' ELSE '360+' END,
       -- Q9: negative balances are overpayment credits, not exposure.
       CASE WHEN c.AMT_BALANCE < 0 THEN 0 ELSE c.AMT_BALANCE END,
       0,
       CASE WHEN c.AMT_CREDIT_LIMIT_ACTUAL > 0
            THEN ROUND(c.AMT_BALANCE / c.AMT_CREDIT_LIMIT_ACTUAL, 4) END
FROM credit_card_balance c;

ANALYZE TABLE stg_installment, stg_account_month;

SELECT 'stg_installment'    AS tbl, COUNT(*) AS rows_built FROM stg_installment
UNION ALL
SELECT 'stg_account_month', COUNT(*) FROM stg_account_month;
