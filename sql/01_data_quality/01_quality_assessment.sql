-- =====================================================================
-- PHASE 5 - DATA QUALITY ASSESSMENT
--
-- Every check below follows the same discipline:
--   WHAT  - what is being tested
--   WHY   - why it matters to this project specifically
--   EXPECT- what we predict, from the Phase 2 CSV measurements
--   then the SQL, whose ACTUAL result is recorded in docs/05_data_quality.md
--
-- Checks DQ-13 and DQ-14 exist to settle two deferred decisions:
--   [D2] delinquency bucket boundaries
--   [D3] SK_DPD vs SK_DPD_DEF as the primary DPD measure
-- =====================================================================
USE loan_portfolio;

SELECT '################ DQ-01  KEY UNIQUENESS ################' AS `check`;
-- WHAT   Re-assert that every declared primary key still holds in InnoDB.
-- WHY    The PKs were declared in Phase 3 from Phase 2 evidence. If any were wrong
--        the load would have failed on a duplicate-key error - it did not. This is
--        belt-and-braces: it proves uniqueness rather than inferring it from silence.
-- EXPECT dup_rows = 0 everywhere.
SELECT 'application'           AS tbl, COUNT(*) - COUNT(DISTINCT SK_ID_CURR)   AS dup_rows FROM application
UNION ALL SELECT 'bureau',              COUNT(*) - COUNT(DISTINCT SK_ID_BUREAU)          FROM bureau
UNION ALL SELECT 'bureau_balance',      COUNT(*) - COUNT(DISTINCT SK_ID_BUREAU, MONTHS_BALANCE) FROM bureau_balance
UNION ALL SELECT 'previous_application',COUNT(*) - COUNT(DISTINCT SK_ID_PREV)            FROM previous_application
UNION ALL SELECT 'pos_cash_balance',    COUNT(*) - COUNT(DISTINCT SK_ID_PREV, MONTHS_BALANCE)   FROM pos_cash_balance
UNION ALL SELECT 'credit_card_balance', COUNT(*) - COUNT(DISTINCT SK_ID_PREV, MONTHS_BALANCE)   FROM credit_card_balance;


SELECT '################ DQ-02  F1 SPLIT PAYMENTS ################' AS `check`;
-- WHAT   Quantify installments settled by more than one payment event.
-- WHY    This is the finding that redefines the repayment module. If AMT_PAYMENT is
--        compared row-by-row to AMT_INSTALMENT, every split installment is misread
--        as an underpayment.
-- EXPECT ~640,905 installments affected; ~99.9% fully settled once summed.
WITH per_installment AS (
    SELECT SK_ID_PREV, NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER,
           COUNT(*)            AS n_payments,
           MAX(AMT_INSTALMENT) AS amt_due,
           SUM(AMT_PAYMENT)    AS amt_paid
    FROM installments_payments
    GROUP BY SK_ID_PREV, NUM_INSTALMENT_VERSION, NUM_INSTALMENT_NUMBER
)
SELECT
    COUNT(*)                                                   AS installments_total,
    SUM(n_payments > 1)                                        AS installments_split,
    ROUND(100.0 * SUM(n_payments > 1) / COUNT(*), 3)           AS pct_split,
    MAX(n_payments)                                            AS max_payments_one_installment,
    SUM(n_payments > 1 AND ABS(amt_paid - amt_due) < 0.01)     AS split_and_fully_settled,
    ROUND(100.0 * SUM(n_payments > 1 AND ABS(amt_paid - amt_due) < 0.01)
                / NULLIF(SUM(n_payments > 1), 0), 2)           AS pct_split_settled
FROM per_installment;

-- WHAT   Size the error that the naive row-by-row comparison would produce.
-- WHY    Turns "this would be wrong" into a measured number - the interview answer.
SELECT
    SUM(AMT_PAYMENT < AMT_INSTALMENT - 0.01)  AS rows_looking_short_naive,
    ROUND(100.0 * SUM(AMT_PAYMENT < AMT_INSTALMENT - 0.01) / COUNT(*), 2) AS pct_naive
FROM installments_payments
WHERE AMT_PAYMENT IS NOT NULL;


SELECT '################ DQ-03  F5 CALENDAR RE-VERSIONING ################' AS `check`;
-- WHAT   Rows added because the payment calendar was re-versioned.
-- WHY    A second, independent row multiplier. Must not be confused with DQ-02.
-- EXPECT 12,861,994 distinct (PREV, NUMBER); ~743,407 extra rows.
SELECT COUNT(*)                                                     AS rows_total,
       COUNT(DISTINCT SK_ID_PREV, NUM_INSTALMENT_NUMBER)            AS distinct_prev_number,
       COUNT(*) - COUNT(DISTINCT SK_ID_PREV, NUM_INSTALMENT_NUMBER) AS extra_rows,
       COUNT(DISTINCT NUM_INSTALMENT_VERSION)                       AS version_levels,
       MAX(NUM_INSTALMENT_VERSION)                                  AS max_version
FROM installments_payments;


SELECT '################ DQ-04  ORPHAN IMPACT ON EXPOSURE ################' AS `check`;
-- WHAT   How much of the POS/cash book loses its exposure proxy because the parent
--        contract is missing from previous_application (finding F3).
-- WHY    Exposure(POS) = CNT_INSTALMENT_FUTURE x AMT_ANNUITY, and AMT_ANNUITY lives in
--        previous_application. No parent row => no exposure. This measures the hole
--        BEFORE we build the collections queue on top of it.
-- EXPECT ~4% of POS contracts orphaned; plus further loss where AMT_ANNUITY is NULL.
SELECT
    COUNT(DISTINCT p.SK_ID_PREV)                                              AS pos_contracts,
    COUNT(DISTINCT CASE WHEN pa.SK_ID_PREV IS NULL THEN p.SK_ID_PREV END)     AS orphan_contracts,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN pa.SK_ID_PREV IS NULL THEN p.SK_ID_PREV END)
                / COUNT(DISTINCT p.SK_ID_PREV), 2)                            AS pct_orphan,
    COUNT(DISTINCT CASE WHEN pa.SK_ID_PREV IS NOT NULL AND pa.AMT_ANNUITY IS NULL
                        THEN p.SK_ID_PREV END)                                AS parent_but_null_annuity,
    ROUND(100.0 * COUNT(DISTINCT CASE WHEN pa.SK_ID_PREV IS NULL
                                       OR pa.AMT_ANNUITY IS NULL THEN p.SK_ID_PREV END)
                / COUNT(DISTINCT p.SK_ID_PREV), 2)                            AS pct_no_exposure_possible
FROM pos_cash_balance p
LEFT JOIN previous_application pa ON pa.SK_ID_PREV = p.SK_ID_PREV;


SELECT '################ DQ-05  F8 DAYS_EMPLOYED SENTINEL ################' AS `check`;
-- WHAT   Confirm in SQL that 365243 encodes "not employed", and measure its risk profile.
-- WHY    18% of rows. Left raw it injects a +1000-year tenure. Decoding it correctly
--        matters because the affected group is LOWER risk, so the error inverts conclusions.
-- EXPECT Pensioner 99.98%, Unemployed 100%, everyone else 0%. TARGET 5.40% vs 8.66%.
SELECT NAME_INCOME_TYPE,
       COUNT(*)                                                    AS rows_in_group,
       SUM(DAYS_EMPLOYED = 365243)                                 AS sentinel_rows,
       ROUND(100.0 * SUM(DAYS_EMPLOYED = 365243) / COUNT(*), 2)    AS pct_sentinel,
       ROUND(100.0 * AVG(TARGET), 4)                               AS target_rate_pct
FROM application
WHERE SOURCE = 'train'
GROUP BY NAME_INCOME_TYPE
ORDER BY sentinel_rows DESC;

SELECT CASE WHEN DAYS_EMPLOYED = 365243 THEN 'sentinel (not employed)' ELSE 'real tenure' END AS grp,
       COUNT(*)                                    AS n,
       ROUND(100.0 * AVG(TARGET), 4)               AS target_rate_pct,
       SUM(OCCUPATION_TYPE IS NULL)                AS occupation_null,
       MIN(DAYS_EMPLOYED)                          AS min_days,
       MAX(DAYS_EMPLOYED)                          AS max_days
FROM application WHERE SOURCE = 'train'
GROUP BY grp;


SELECT '################ DQ-06  F12 SYSTEMATIC NULL DAYS_* ################' AS `check`;
-- WHAT   Five DAYS_* columns in previous_application share an identical 40.30% null rate.
--        Test the hypothesis that nulls occur exactly when the application was not approved.
-- WHY    If nulls are structural (no schedule exists for a refused application) they are
--        not a defect and must not be "fixed". If they are random, vintage analysis is at risk.
-- EXPECT Nulls concentrated in Refused / Canceled / Unused offer.
SELECT NAME_CONTRACT_STATUS,
       COUNT(*)                                                       AS rows_in_status,
       SUM(DAYS_FIRST_DUE IS NULL)                                    AS null_first_due,
       ROUND(100.0 * SUM(DAYS_FIRST_DUE IS NULL) / COUNT(*), 2)       AS pct_null_first_due,
       SUM(DAYS_LAST_DUE IS NULL)                                     AS null_last_due,
       SUM(DAYS_TERMINATION IS NULL)                                  AS null_termination
FROM previous_application
GROUP BY NAME_CONTRACT_STATUS
ORDER BY rows_in_status DESC;


SELECT '################ DQ-07  365243 IN previous_application ################' AS `check`;
-- WHAT   The same sentinel appears in date columns of previous_application.
-- WHY    DAYS_LAST_DUE / DAYS_TERMINATION drive contract-age and vintage logic. A sentinel
--        read as a real date would place terminations ~1000 years in the future.
-- EXPECT DAYS_FIRST_DRAWING 55.95%; DAYS_TERMINATION 13.53%; DAYS_LAST_DUE 12.65%.
SELECT 'DAYS_FIRST_DRAWING' AS col, SUM(DAYS_FIRST_DRAWING = 365243) AS sentinel_rows,
       ROUND(100.0*SUM(DAYS_FIRST_DRAWING = 365243)/COUNT(*),2) AS pct FROM previous_application
UNION ALL SELECT 'DAYS_FIRST_DUE',            SUM(DAYS_FIRST_DUE = 365243),
       ROUND(100.0*SUM(DAYS_FIRST_DUE = 365243)/COUNT(*),2) FROM previous_application
UNION ALL SELECT 'DAYS_LAST_DUE_1ST_VERSION', SUM(DAYS_LAST_DUE_1ST_VERSION = 365243),
       ROUND(100.0*SUM(DAYS_LAST_DUE_1ST_VERSION = 365243)/COUNT(*),2) FROM previous_application
UNION ALL SELECT 'DAYS_LAST_DUE',             SUM(DAYS_LAST_DUE = 365243),
       ROUND(100.0*SUM(DAYS_LAST_DUE = 365243)/COUNT(*),2) FROM previous_application
UNION ALL SELECT 'DAYS_TERMINATION',          SUM(DAYS_TERMINATION = 365243),
       ROUND(100.0*SUM(DAYS_TERMINATION = 365243)/COUNT(*),2) FROM previous_application;


SELECT '################ DQ-08  IMPOSSIBLE VALUES ################' AS `check`;
-- WHAT   Values that cannot exist in reality.
-- WHY    Negative debt is not a small debt - it is a sign the field means something else
--        (or was mis-signed). We must decide treatment before using it as exposure.
-- EXPECT 8,418 negative AMT_CREDIT_SUM_DEBT, min -4,705,600.
SELECT 'bureau.AMT_CREDIT_SUM_DEBT < 0'  AS issue, COUNT(*) AS n,
       MIN(AMT_CREDIT_SUM_DEBT) AS min_val, ROUND(AVG(AMT_CREDIT_SUM_DEBT),0) AS avg_val
FROM bureau WHERE AMT_CREDIT_SUM_DEBT < 0
UNION ALL
SELECT 'bureau.AMT_CREDIT_SUM_DEBT > AMT_CREDIT_SUM (debt exceeds facility)', COUNT(*),
       NULL, NULL
FROM bureau WHERE AMT_CREDIT_SUM_DEBT > AMT_CREDIT_SUM
UNION ALL
SELECT 'credit_card AMT_BALANCE < 0', COUNT(*), MIN(AMT_BALANCE), ROUND(AVG(AMT_BALANCE),0)
FROM credit_card_balance WHERE AMT_BALANCE < 0
UNION ALL
SELECT 'credit_card utilisation > 1.5 (balance far above limit)', COUNT(*), NULL, NULL
FROM credit_card_balance
WHERE AMT_CREDIT_LIMIT_ACTUAL > 0 AND AMT_BALANCE / AMT_CREDIT_LIMIT_ACTUAL > 1.5;

-- WHAT   Temporal impossibility: a payment recorded far earlier than the due date.
-- WHY    Phase 2 saw a minimum of -3,189 days (8.7 years early). Plausible? Test the spread.
SELECT CASE
         WHEN DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT < -365 THEN 'paid >1yr early (suspect)'
         WHEN DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT <    0 THEN 'paid early'
         WHEN DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT =    0 THEN 'paid on due date'
         WHEN DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT <=  30 THEN 'late 1-30'
         WHEN DAYS_ENTRY_PAYMENT - DAYS_INSTALMENT <=  90 THEN 'late 31-90'
         ELSE 'late 90+'
       END AS timing_band,
       COUNT(*) AS n,
       ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS pct
FROM installments_payments
WHERE DAYS_ENTRY_PAYMENT IS NOT NULL
GROUP BY timing_band
ORDER BY n DESC;


SELECT '################ DQ-09  PLACEHOLDER CATEGORIES ################' AS `check`;
-- WHAT   XNA / XAP / Unknown are placeholder codes, not real categories.
-- WHY    Grouping by a column where 40% of rows say "XNA" produces a chart whose largest
--        bar is meaningless. We must know the size before choosing dimensions for Power BI.
SELECT 'application.CODE_GENDER = XNA'        AS placeholder, COUNT(*) AS n FROM application WHERE CODE_GENDER='XNA'
UNION ALL SELECT 'application.NAME_FAMILY_STATUS = Unknown', COUNT(*) FROM application WHERE NAME_FAMILY_STATUS='Unknown'
UNION ALL SELECT 'application.ORGANIZATION_TYPE = XNA',      COUNT(*) FROM application WHERE ORGANIZATION_TYPE='XNA'
UNION ALL SELECT 'application.OCCUPATION_TYPE IS NULL',      COUNT(*) FROM application WHERE OCCUPATION_TYPE IS NULL
UNION ALL SELECT 'prev.NAME_CASH_LOAN_PURPOSE in (XNA,XAP)', COUNT(*) FROM previous_application WHERE NAME_CASH_LOAN_PURPOSE IN ('XNA','XAP')
UNION ALL SELECT 'prev.NAME_YIELD_GROUP = XNA',              COUNT(*) FROM previous_application WHERE NAME_YIELD_GROUP='XNA'
UNION ALL SELECT 'prev.NAME_PORTFOLIO = XNA',                COUNT(*) FROM previous_application WHERE NAME_PORTFOLIO='XNA'
UNION ALL SELECT 'prev.NAME_PRODUCT_TYPE = XNA',             COUNT(*) FROM previous_application WHERE NAME_PRODUCT_TYPE='XNA';


SELECT '################ DQ-10  OUTLIERS ################' AS `check`;
-- WHAT   Extreme values that would distort any mean.
-- WHY    AMT_INCOME_TOTAL has a max 247x its own p99. One row can move a segment average.
SELECT COUNT(*)                       AS n,
       MIN(AMT_INCOME_TOTAL)          AS min_income,
       ROUND(AVG(AMT_INCOME_TOTAL),0) AS mean_income,
       MAX(AMT_INCOME_TOTAL)          AS max_income,
       SUM(AMT_INCOME_TOTAL > 10000000) AS above_10m,
       SUM(AMT_INCOME_TOTAL > 2000000)  AS above_2m
FROM application WHERE SOURCE='train';


SELECT '################ DQ-11  F11 BUREAU STATUS X ################' AS `check`;
-- WHAT   Distribution of bureau_balance.STATUS, including the unknown code X.
-- WHY    21% unknown. Treating X as "current" would understate external delinquency
--        across a fifth of the history. It must be excluded explicitly, not by accident.
SELECT STATUS,
       CASE STATUS WHEN 'C' THEN 'closed' WHEN 'X' THEN 'UNKNOWN'
                   WHEN '0' THEN 'no DPD' WHEN '1' THEN 'DPD 1-30'
                   WHEN '2' THEN 'DPD 31-60' WHEN '3' THEN 'DPD 61-90'
                   WHEN '4' THEN 'DPD 91-120' WHEN '5' THEN 'DPD 120+ / written off'
       END AS meaning,
       COUNT(*) AS n,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 4) AS pct
FROM bureau_balance
GROUP BY STATUS ORDER BY n DESC;


SELECT '################ DQ-12  F4 COVERAGE ################' AS `check`;
-- WHAT   What share of the customer base each behavioural table actually covers.
-- WHY    Every portfolio metric must be scoped. "Delinquency rate" is meaningless without
--        stating the denominator population.
SELECT 'customers total (train+test)'  AS population, COUNT(*) AS n FROM application
UNION ALL SELECT 'with any previous_application', COUNT(DISTINCT SK_ID_CURR) FROM previous_application
UNION ALL SELECT 'with any pos_cash history',     COUNT(DISTINCT SK_ID_CURR) FROM pos_cash_balance
UNION ALL SELECT 'with any credit_card history',  COUNT(DISTINCT SK_ID_CURR) FROM credit_card_balance
UNION ALL SELECT 'with any installment history',  COUNT(DISTINCT SK_ID_CURR) FROM installments_payments
UNION ALL SELECT 'with any bureau credit',        COUNT(DISTINCT SK_ID_CURR) FROM bureau;

SELECT COUNT(DISTINCT b.SK_ID_BUREAU)                                        AS bureau_credits,
       COUNT(DISTINCT bb.SK_ID_BUREAU)                                       AS with_monthly_history,
       ROUND(100.0*COUNT(DISTINCT bb.SK_ID_BUREAU)/COUNT(DISTINCT b.SK_ID_BUREAU),2) AS pct_covered
FROM bureau b LEFT JOIN bureau_balance bb ON bb.SK_ID_BUREAU = b.SK_ID_BUREAU;


SELECT '################ DQ-13  [D2] DPD DISTRIBUTION ################' AS `check`;
-- WHAT   The full DPD shape, on ACTIVE account-months only.
-- WHY    This decides the bucket boundaries. Phase 2 showed the distribution is bimodal:
--        a mild-lateness cluster and an absorbing tail. Restricting to Active removes
--        closed/completed accounts that would dilute the picture.
-- EXPECT 31-60 and 61-90 nearly empty; 360+ dominant within 90+.
SELECT 'pos_cash' AS src,
       CASE WHEN SK_DPD = 0 THEN '0 current'
            WHEN SK_DPD <=  30 THEN '1-30'   WHEN SK_DPD <=  60 THEN '31-60'
            WHEN SK_DPD <=  90 THEN '61-90'  WHEN SK_DPD <= 180 THEN '91-180'
            WHEN SK_DPD <= 360 THEN '181-360' ELSE '360+' END AS bucket,
       COUNT(*) AS account_months,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 4) AS pct
FROM pos_cash_balance WHERE NAME_CONTRACT_STATUS = 'Active'
GROUP BY bucket
UNION ALL
SELECT 'credit_card' AS src,
       CASE WHEN SK_DPD = 0 THEN '0 current'
            WHEN SK_DPD <=  30 THEN '1-30'   WHEN SK_DPD <=  60 THEN '31-60'
            WHEN SK_DPD <=  90 THEN '61-90'  WHEN SK_DPD <= 180 THEN '91-180'
            WHEN SK_DPD <= 360 THEN '181-360' ELSE '360+' END AS bucket,
       COUNT(*) AS account_months, ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 4) AS pct
FROM credit_card_balance WHERE NAME_CONTRACT_STATUS = 'Active'
GROUP BY bucket
ORDER BY src, bucket;

-- WHAT   How many DISTINCT ACCOUNTS ever reach each bucket (not account-months).
-- WHY    Roll-rate denominators are accounts, not months. If only a few thousand accounts
--        ever touch 61-90, transition rates through it will be unstable and must be
--        reported with counts.
SELECT CASE WHEN mx = 0 THEN '0 never delinquent'
            WHEN mx <=  30 THEN 'peaked 1-30'   WHEN mx <=  60 THEN 'peaked 31-60'
            WHEN mx <=  90 THEN 'peaked 61-90'  WHEN mx <= 180 THEN 'peaked 91-180'
            WHEN mx <= 360 THEN 'peaked 181-360' ELSE 'peaked 360+' END AS worst_bucket_reached,
       COUNT(*) AS accounts,
       ROUND(100.0*COUNT(*)/SUM(COUNT(*)) OVER (), 4) AS pct
FROM (SELECT SK_ID_PREV, MAX(SK_DPD) AS mx FROM pos_cash_balance GROUP BY SK_ID_PREV) t
GROUP BY worst_bucket_reached ORDER BY accounts DESC;


SELECT '################ DQ-14  [D3] SK_DPD vs SK_DPD_DEF ################' AS `check`;
-- WHAT   How much delinquency disappears under the tolerance-adjusted measure.
-- WHY    Choosing the wrong one either inflates the collections queue with trivial
--        balances, or empties the middle buckets and makes roll rates impossible.
-- EXPECT ~61% of POS delinquent months vanish under SK_DPD_DEF.
SELECT 'pos_cash' AS src,
       SUM(SK_DPD > 0)                                          AS delinq_sk_dpd,
       SUM(SK_DPD_DEF > 0)                                      AS delinq_sk_dpd_def,
       SUM(SK_DPD > 0 AND SK_DPD_DEF = 0)                       AS vanishes_under_def,
       ROUND(100.0*SUM(SK_DPD > 0 AND SK_DPD_DEF = 0)/NULLIF(SUM(SK_DPD > 0),0),2) AS pct_vanishing,
       SUM(SK_DPD BETWEEN 31 AND 90)                            AS mid_bucket_sk_dpd,
       SUM(SK_DPD_DEF BETWEEN 31 AND 90)                        AS mid_bucket_def
FROM pos_cash_balance
UNION ALL
SELECT 'credit_card',
       SUM(SK_DPD > 0), SUM(SK_DPD_DEF > 0), SUM(SK_DPD > 0 AND SK_DPD_DEF = 0),
       ROUND(100.0*SUM(SK_DPD > 0 AND SK_DPD_DEF = 0)/NULLIF(SUM(SK_DPD > 0),0),2),
       SUM(SK_DPD BETWEEN 31 AND 90), SUM(SK_DPD_DEF BETWEEN 31 AND 90)
FROM credit_card_balance;


SELECT '################ DQ-15  MISSINGNESS IS NOT RANDOM ################' AS `check`;
-- WHAT   Does the presence/absence of EXT_SOURCE_1 relate to the outcome?
-- WHY    If missingness correlates with default, dropping or mean-filling those rows
--        introduces bias. This decides how M10 may use the field.
SELECT CASE WHEN EXT_SOURCE_1 IS NULL THEN 'EXT_SOURCE_1 missing' ELSE 'present' END AS grp,
       COUNT(*)                      AS n,
       ROUND(100.0*AVG(TARGET), 4)   AS target_rate_pct
FROM application WHERE SOURCE='train' GROUP BY grp
UNION ALL
SELECT CASE WHEN EXT_SOURCE_3 IS NULL THEN 'EXT_SOURCE_3 missing' ELSE 'present' END,
       COUNT(*), ROUND(100.0*AVG(TARGET), 4)
FROM application WHERE SOURCE='train' GROUP BY 1;
