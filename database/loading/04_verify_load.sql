-- =====================================================================
-- Phase 4 - load verification.
--
-- Nothing downstream may be trusted until this passes. Every number here is
-- compared against a figure MEASURED from the CSVs in Phase 2, so a silent
-- truncation, a dropped row or a mangled quote shows up as a mismatch.
-- =====================================================================
USE loan_portfolio;

-- ---------------------------------------------------------------------
-- 1. ROW COUNT RECONCILIATION  (expected values measured in Phase 2)
-- ---------------------------------------------------------------------
SELECT 'application (train)'   AS tbl, COUNT(*) AS actual,    307511 AS expected,
       COUNT(*) -    307511 AS diff FROM application WHERE SOURCE='train'
UNION ALL SELECT 'application (test)',  COUNT(*),     48744, COUNT(*) -     48744 FROM application WHERE SOURCE='test'
UNION ALL SELECT 'bureau',               COUNT(*),   1716428, COUNT(*) -   1716428 FROM bureau
UNION ALL SELECT 'bureau_balance',       COUNT(*),  27299925, COUNT(*) -  27299925 FROM bureau_balance
UNION ALL SELECT 'previous_application', COUNT(*),   1670214, COUNT(*) -   1670214 FROM previous_application
UNION ALL SELECT 'pos_cash_balance',     COUNT(*),  10001358, COUNT(*) -  10001358 FROM pos_cash_balance
UNION ALL SELECT 'credit_card_balance',  COUNT(*),   3840312, COUNT(*) -   3840312 FROM credit_card_balance
UNION ALL SELECT 'installments_payments',COUNT(*),  13605401, COUNT(*) -  13605401 FROM installments_payments;

-- ---------------------------------------------------------------------
-- 2. VALUE-RANGE CHECKS - did anything get truncated?
--    Phase 2 measured these maxima. A smaller value here means silent damage.
-- ---------------------------------------------------------------------
SELECT 'pos.SK_DPD'                  AS col, MAX(SK_DPD)                AS actual_max, 4231 AS expected_max FROM pos_cash_balance
UNION ALL SELECT 'pos.SK_DPD_DEF',        MAX(SK_DPD_DEF),               3595 FROM pos_cash_balance
UNION ALL SELECT 'cc.SK_DPD',             MAX(SK_DPD),                   3260 FROM credit_card_balance
UNION ALL SELECT 'inst.NUM_INSTALMENT_NUMBER', MAX(NUM_INSTALMENT_NUMBER), 277 FROM installments_payments
UNION ALL SELECT 'bureau.CREDIT_DAY_OVERDUE',  MAX(CREDIT_DAY_OVERDUE),  2792 FROM bureau
UNION ALL SELECT 'app.DAYS_EMPLOYED (sentinel)', MAX(DAYS_EMPLOYED),   365243 FROM application;

-- Money must survive to 3 decimal places, not be rounded to integers.
SELECT MAX(AMT_INSTALMENT)   AS max_amt_instalment,   -- expect 3771487.845
       MAX(AMT_PAYMENT)      AS max_amt_payment,      -- expect 3771487.845
       SUM(AMT_PAYMENT)      AS total_paid
FROM installments_payments;

-- ---------------------------------------------------------------------
-- 3. NULL HANDLING - empty CSV fields must be NULL, never 0 or ''
--    Expected counts measured in Phase 2.
-- ---------------------------------------------------------------------
SELECT 'inst.DAYS_ENTRY_PAYMENT' AS col, SUM(DAYS_ENTRY_PAYMENT IS NULL) AS nulls, 2905 AS expected FROM installments_payments
UNION ALL SELECT 'inst.AMT_PAYMENT',   SUM(AMT_PAYMENT IS NULL),      2905 FROM installments_payments
UNION ALL SELECT 'pos.CNT_INSTALMENT', SUM(CNT_INSTALMENT IS NULL),  26071 FROM pos_cash_balance
UNION ALL SELECT 'app.AMT_ANNUITY',    SUM(AMT_ANNUITY IS NULL),        12 FROM application WHERE SOURCE='train'
UNION ALL SELECT 'app.EXT_SOURCE_1',   SUM(EXT_SOURCE_1 IS NULL),   173378 FROM application WHERE SOURCE='train'
UNION ALL SELECT 'bureau.AMT_ANNUITY', SUM(AMT_ANNUITY IS NULL),   1226791 FROM bureau;

-- ---------------------------------------------------------------------
-- 4. QUOTED-FIELD CHECK - values containing commas must have survived intact
--    e.g. 'Spouse, partner'.  A broken quote setting would shred these rows.
-- ---------------------------------------------------------------------
SELECT NAME_TYPE_SUITE, COUNT(*) AS n
FROM application WHERE SOURCE='train' AND NAME_TYPE_SUITE LIKE '%,%'
GROUP BY NAME_TYPE_SUITE;                      -- expect 'Spouse, partner' = 11370

SELECT COUNT(DISTINCT ORGANIZATION_TYPE) AS org_types  -- expect 58
FROM application WHERE SOURCE='train';

-- ---------------------------------------------------------------------
-- 5. BASE RATE - the anchor for every early-warning claim in M11
-- ---------------------------------------------------------------------
SELECT COUNT(*)                       AS n,
       SUM(TARGET)                    AS defaults,
       ROUND(AVG(TARGET)*100, 4)      AS target_rate_pct   -- expect 8.0729
FROM application WHERE SOURCE='train';

SELECT SUM(TARGET IS NULL) AS test_rows_without_target    -- expect 48744
FROM application WHERE SOURCE='test';

-- ---------------------------------------------------------------------
-- 6. REFERENTIAL INTEGRITY - re-measure the Phase 2 orphan rates IN-DATABASE.
--    We declared no FK constraints (Phase 3), so these must be verified, not assumed.
-- ---------------------------------------------------------------------
SELECT 'bureau -> application' AS rel,
       COUNT(*) AS orphan_ids, 0 AS expected           -- expect 0
FROM (SELECT DISTINCT b.SK_ID_CURR FROM bureau b
      LEFT JOIN application a ON a.SK_ID_CURR = b.SK_ID_CURR
      WHERE a.SK_ID_CURR IS NULL) x
UNION ALL
SELECT 'previous_application -> application', COUNT(*), 0
FROM (SELECT DISTINCT p.SK_ID_CURR FROM previous_application p
      LEFT JOIN application a ON a.SK_ID_CURR = p.SK_ID_CURR
      WHERE a.SK_ID_CURR IS NULL) x
UNION ALL
SELECT 'pos_cash -> previous_application', COUNT(*), 37422      -- genuine orphans (F3)
FROM (SELECT DISTINCT c.SK_ID_PREV FROM pos_cash_balance c
      LEFT JOIN previous_application p ON p.SK_ID_PREV = c.SK_ID_PREV
      WHERE p.SK_ID_PREV IS NULL) x
UNION ALL
SELECT 'credit_card -> previous_application', COUNT(*), 11372
FROM (SELECT DISTINCT c.SK_ID_PREV FROM credit_card_balance c
      LEFT JOIN previous_application p ON p.SK_ID_PREV = c.SK_ID_PREV
      WHERE p.SK_ID_PREV IS NULL) x
UNION ALL
SELECT 'installments -> previous_application', COUNT(*), 38847
FROM (SELECT DISTINCT i.SK_ID_PREV FROM installments_payments i
      LEFT JOIN previous_application p ON p.SK_ID_PREV = i.SK_ID_PREV
      WHERE p.SK_ID_PREV IS NULL) x
UNION ALL
SELECT 'bureau_balance -> bureau', COUNT(*), 43041
FROM (SELECT DISTINCT bb.SK_ID_BUREAU FROM bureau_balance bb
      LEFT JOIN bureau b ON b.SK_ID_BUREAU = bb.SK_ID_BUREAU
      WHERE b.SK_ID_BUREAU IS NULL) x;

-- ---------------------------------------------------------------------
-- 7. GRAIN RE-CONFIRMATION - F1 must reproduce in the database
-- ---------------------------------------------------------------------
SELECT COUNT(*)                                                  AS rows_total,      -- 13605401
       COUNT(DISTINCT SK_ID_PREV, NUM_INSTALMENT_VERSION,
                      NUM_INSTALMENT_NUMBER)                     AS distinct_triple, -- 12951918
       COUNT(*) - COUNT(DISTINCT SK_ID_PREV, NUM_INSTALMENT_VERSION,
                                 NUM_INSTALMENT_NUMBER)          AS split_payments   -- 653483
FROM installments_payments;

-- ---------------------------------------------------------------------
-- 8. ACTUAL STORAGE - replaces the Phase 3 estimate of ~3.8 GB
-- ---------------------------------------------------------------------
SELECT TABLE_NAME,
       TABLE_ROWS                                  AS approx_rows,
       ROUND(DATA_LENGTH /1024/1024, 1)            AS data_mb,
       ROUND(INDEX_LENGTH/1024/1024, 1)            AS index_mb,
       ROUND((DATA_LENGTH+INDEX_LENGTH)/1024/1024, 1) AS total_mb
FROM information_schema.TABLES
WHERE TABLE_SCHEMA = 'loan_portfolio'
ORDER BY (DATA_LENGTH+INDEX_LENGTH) DESC;

SELECT ROUND(SUM(DATA_LENGTH+INDEX_LENGTH)/1024/1024/1024, 2) AS total_gb
FROM information_schema.TABLES WHERE TABLE_SCHEMA = 'loan_portfolio';
