# Phase 2 — Column Profile (measured)


## `application_train.csv` — 307,511 rows, 122 columns

| column | dtype | null % | min | max | mean | negatives |
|---|---|---:|---:|---:|---:|---:|
| SK_ID_CURR | int64 | 0.00 | 100,002.00 | 456,255.00 | 278,180.52 |  |
| TARGET | int64 | 0.00 | 0.00 | 1.00 | 0.08 |  |
| NAME_CONTRACT_TYPE | str | 0.00 | - | - | - |  |
| CODE_GENDER | str | 0.00 | - | - | - |  |
| FLAG_OWN_CAR | str | 0.00 | - | - | - |  |
| FLAG_OWN_REALTY | str | 0.00 | - | - | - |  |
| CNT_CHILDREN | int64 | 0.00 | 0.00 | 19.00 | 0.42 |  |
| AMT_INCOME_TOTAL | float64 | 0.00 | 25,650.00 | 117,000,000.00 | 168,797.92 |  |
| AMT_CREDIT | float64 | 0.00 | 45,000.00 | 4,050,000.00 | 599,026.00 |  |
| AMT_ANNUITY | float64 | 0.00 | 1,615.50 | 258,025.50 | 27,108.57 |  |
| AMT_GOODS_PRICE | float64 | 0.09 | 40,500.00 | 4,050,000.00 | 538,396.21 |  |
| NAME_TYPE_SUITE | str | 0.42 | - | - | - |  |
| NAME_INCOME_TYPE | str | 0.00 | - | - | - |  |
| NAME_EDUCATION_TYPE | str | 0.00 | - | - | - |  |
| NAME_FAMILY_STATUS | str | 0.00 | - | - | - |  |
| NAME_HOUSING_TYPE | str | 0.00 | - | - | - |  |
| REGION_POPULATION_RELATIVE | float64 | 0.00 | 0.00 | 0.07 | 0.02 |  |
| DAYS_BIRTH | int64 | 0.00 | -25,229.00 | -7,489.00 | -16,037.00 | 307,511 |
| DAYS_EMPLOYED | int64 | 0.00 | -17,912.00 | 365,243.00 | 63,815.05 | 252,135 |
| DAYS_REGISTRATION | float64 | 0.00 | -24,672.00 | 0.00 | -4,986.12 | 307,431 |
| DAYS_ID_PUBLISH | int64 | 0.00 | -7,197.00 | 0.00 | -2,994.20 | 307,495 |
| OWN_CAR_AGE | float64 | 65.99 | 0.00 | 91.00 | 12.06 |  |
| FLAG_MOBIL | int64 | 0.00 | 0.00 | 1.00 | 1.00 |  |
| FLAG_EMP_PHONE | int64 | 0.00 | 0.00 | 1.00 | 0.82 |  |
| FLAG_WORK_PHONE | int64 | 0.00 | 0.00 | 1.00 | 0.20 |  |
| FLAG_CONT_MOBILE | int64 | 0.00 | 0.00 | 1.00 | 1.00 |  |
| FLAG_PHONE | int64 | 0.00 | 0.00 | 1.00 | 0.28 |  |
| FLAG_EMAIL | int64 | 0.00 | 0.00 | 1.00 | 0.06 |  |
| OCCUPATION_TYPE | str | 31.35 | - | - | - |  |
| CNT_FAM_MEMBERS | float64 | 0.00 | 1.00 | 20.00 | 2.15 |  |
| REGION_RATING_CLIENT | int64 | 0.00 | 1.00 | 3.00 | 2.05 |  |
| REGION_RATING_CLIENT_W_CITY | int64 | 0.00 | 1.00 | 3.00 | 2.03 |  |
| WEEKDAY_APPR_PROCESS_START | str | 0.00 | - | - | - |  |
| HOUR_APPR_PROCESS_START | int64 | 0.00 | 0.00 | 23.00 | 12.06 |  |
| REG_REGION_NOT_LIVE_REGION | int64 | 0.00 | 0.00 | 1.00 | 0.02 |  |
| REG_REGION_NOT_WORK_REGION | int64 | 0.00 | 0.00 | 1.00 | 0.05 |  |
| LIVE_REGION_NOT_WORK_REGION | int64 | 0.00 | 0.00 | 1.00 | 0.04 |  |
| REG_CITY_NOT_LIVE_CITY | int64 | 0.00 | 0.00 | 1.00 | 0.08 |  |
| REG_CITY_NOT_WORK_CITY | int64 | 0.00 | 0.00 | 1.00 | 0.23 |  |
| LIVE_CITY_NOT_WORK_CITY | int64 | 0.00 | 0.00 | 1.00 | 0.18 |  |
| ORGANIZATION_TYPE | str | 0.00 | - | - | - |  |
| EXT_SOURCE_1 | float64 | 56.38 | 0.01 | 0.96 | 0.50 |  |
| EXT_SOURCE_2 | float64 | 0.21 | 0.00 | 0.85 | 0.51 |  |
| EXT_SOURCE_3 | float64 | 19.83 | 0.00 | 0.90 | 0.51 |  |
| APARTMENTS_AVG | float64 | 50.75 | 0.00 | 1.00 | 0.12 |  |
| BASEMENTAREA_AVG | float64 | 58.52 | 0.00 | 1.00 | 0.09 |  |
| YEARS_BEGINEXPLUATATION_AVG | float64 | 48.78 | 0.00 | 1.00 | 0.98 |  |
| YEARS_BUILD_AVG | float64 | 66.50 | 0.00 | 1.00 | 0.75 |  |
| COMMONAREA_AVG | float64 | 69.87 | 0.00 | 1.00 | 0.04 |  |
| ELEVATORS_AVG | float64 | 53.30 | 0.00 | 1.00 | 0.08 |  |
| ENTRANCES_AVG | float64 | 50.35 | 0.00 | 1.00 | 0.15 |  |
| FLOORSMAX_AVG | float64 | 49.76 | 0.00 | 1.00 | 0.23 |  |
| FLOORSMIN_AVG | float64 | 67.85 | 0.00 | 1.00 | 0.23 |  |
| LANDAREA_AVG | float64 | 59.38 | 0.00 | 1.00 | 0.07 |  |
| LIVINGAPARTMENTS_AVG | float64 | 68.35 | 0.00 | 1.00 | 0.10 |  |
| LIVINGAREA_AVG | float64 | 50.19 | 0.00 | 1.00 | 0.11 |  |
| NONLIVINGAPARTMENTS_AVG | float64 | 69.43 | 0.00 | 1.00 | 0.01 |  |
| NONLIVINGAREA_AVG | float64 | 55.18 | 0.00 | 1.00 | 0.03 |  |
| APARTMENTS_MODE | float64 | 50.75 | 0.00 | 1.00 | 0.11 |  |
| BASEMENTAREA_MODE | float64 | 58.52 | 0.00 | 1.00 | 0.09 |  |
| YEARS_BEGINEXPLUATATION_MODE | float64 | 48.78 | 0.00 | 1.00 | 0.98 |  |
| YEARS_BUILD_MODE | float64 | 66.50 | 0.00 | 1.00 | 0.76 |  |
| COMMONAREA_MODE | float64 | 69.87 | 0.00 | 1.00 | 0.04 |  |
| ELEVATORS_MODE | float64 | 53.30 | 0.00 | 1.00 | 0.07 |  |
| ENTRANCES_MODE | float64 | 50.35 | 0.00 | 1.00 | 0.15 |  |
| FLOORSMAX_MODE | float64 | 49.76 | 0.00 | 1.00 | 0.22 |  |
| FLOORSMIN_MODE | float64 | 67.85 | 0.00 | 1.00 | 0.23 |  |
| LANDAREA_MODE | float64 | 59.38 | 0.00 | 1.00 | 0.06 |  |
| LIVINGAPARTMENTS_MODE | float64 | 68.35 | 0.00 | 1.00 | 0.11 |  |
| LIVINGAREA_MODE | float64 | 50.19 | 0.00 | 1.00 | 0.11 |  |
| NONLIVINGAPARTMENTS_MODE | float64 | 69.43 | 0.00 | 1.00 | 0.01 |  |
| NONLIVINGAREA_MODE | float64 | 55.18 | 0.00 | 1.00 | 0.03 |  |
| APARTMENTS_MEDI | float64 | 50.75 | 0.00 | 1.00 | 0.12 |  |
| BASEMENTAREA_MEDI | float64 | 58.52 | 0.00 | 1.00 | 0.09 |  |
| YEARS_BEGINEXPLUATATION_MEDI | float64 | 48.78 | 0.00 | 1.00 | 0.98 |  |
| YEARS_BUILD_MEDI | float64 | 66.50 | 0.00 | 1.00 | 0.76 |  |
| COMMONAREA_MEDI | float64 | 69.87 | 0.00 | 1.00 | 0.04 |  |
| ELEVATORS_MEDI | float64 | 53.30 | 0.00 | 1.00 | 0.08 |  |
| ENTRANCES_MEDI | float64 | 50.35 | 0.00 | 1.00 | 0.15 |  |
| FLOORSMAX_MEDI | float64 | 49.76 | 0.00 | 1.00 | 0.23 |  |
| FLOORSMIN_MEDI | float64 | 67.85 | 0.00 | 1.00 | 0.23 |  |
| LANDAREA_MEDI | float64 | 59.38 | 0.00 | 1.00 | 0.07 |  |
| LIVINGAPARTMENTS_MEDI | float64 | 68.35 | 0.00 | 1.00 | 0.10 |  |
| LIVINGAREA_MEDI | float64 | 50.19 | 0.00 | 1.00 | 0.11 |  |
| NONLIVINGAPARTMENTS_MEDI | float64 | 69.43 | 0.00 | 1.00 | 0.01 |  |
| NONLIVINGAREA_MEDI | float64 | 55.18 | 0.00 | 1.00 | 0.03 |  |
| FONDKAPREMONT_MODE | str | 68.39 | - | - | - |  |
| HOUSETYPE_MODE | str | 50.18 | - | - | - |  |
| TOTALAREA_MODE | float64 | 48.27 | 0.00 | 1.00 | 0.10 |  |
| WALLSMATERIAL_MODE | str | 50.84 | - | - | - |  |
| EMERGENCYSTATE_MODE | str | 47.40 | - | - | - |  |
| OBS_30_CNT_SOCIAL_CIRCLE | float64 | 0.33 | 0.00 | 348.00 | 1.42 |  |
| DEF_30_CNT_SOCIAL_CIRCLE | float64 | 0.33 | 0.00 | 34.00 | 0.14 |  |
| OBS_60_CNT_SOCIAL_CIRCLE | float64 | 0.33 | 0.00 | 344.00 | 1.41 |  |
| DEF_60_CNT_SOCIAL_CIRCLE | float64 | 0.33 | 0.00 | 24.00 | 0.10 |  |
| DAYS_LAST_PHONE_CHANGE | float64 | 0.00 | -4,292.00 | 0.00 | -962.86 | 269,838 |
| FLAG_DOCUMENT_2 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_3 | int64 | 0.00 | 0.00 | 1.00 | 0.71 |  |
| FLAG_DOCUMENT_4 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_5 | int64 | 0.00 | 0.00 | 1.00 | 0.02 |  |
| FLAG_DOCUMENT_6 | int64 | 0.00 | 0.00 | 1.00 | 0.09 |  |
| FLAG_DOCUMENT_7 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_8 | int64 | 0.00 | 0.00 | 1.00 | 0.08 |  |
| FLAG_DOCUMENT_9 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_10 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_11 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_12 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_13 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_14 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_15 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_16 | int64 | 0.00 | 0.00 | 1.00 | 0.01 |  |
| FLAG_DOCUMENT_17 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_18 | int64 | 0.00 | 0.00 | 1.00 | 0.01 |  |
| FLAG_DOCUMENT_19 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_20 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| FLAG_DOCUMENT_21 | int64 | 0.00 | 0.00 | 1.00 | 0.00 |  |
| AMT_REQ_CREDIT_BUREAU_HOUR | float64 | 13.50 | 0.00 | 4.00 | 0.01 |  |
| AMT_REQ_CREDIT_BUREAU_DAY | float64 | 13.50 | 0.00 | 9.00 | 0.01 |  |
| AMT_REQ_CREDIT_BUREAU_WEEK | float64 | 13.50 | 0.00 | 8.00 | 0.03 |  |
| AMT_REQ_CREDIT_BUREAU_MON | float64 | 13.50 | 0.00 | 27.00 | 0.27 |  |
| AMT_REQ_CREDIT_BUREAU_QRT | float64 | 13.50 | 0.00 | 261.00 | 0.27 |  |
| AMT_REQ_CREDIT_BUREAU_YEAR | float64 | 13.50 | 0.00 | 25.00 | 1.90 |  |

**`NAME_CONTRACT_TYPE`** (2 levels): Cash loans=278,232, Revolving loans=29,279


**`CODE_GENDER`** (3 levels): F=202,448, M=105,059, XNA=4


**`FLAG_OWN_CAR`** (2 levels): N=202,924, Y=104,587


**`FLAG_OWN_REALTY`** (2 levels): Y=213,312, N=94,199


**`NAME_TYPE_SUITE`** (7 levels): Unaccompanied=248,526, Family=40,149, Spouse, partner=11,370, Children=3,267, Other_B=1,770, Other_A=866, Group of people=271


**`NAME_INCOME_TYPE`** (8 levels): Working=158,774, Commercial associate=71,617, Pensioner=55,362, State servant=21,703, Unemployed=22, Student=18, Businessman=10, Maternity leave=5


**`NAME_EDUCATION_TYPE`** (5 levels): Secondary / secondary special=218,391, Higher education=74,863, Incomplete higher=10,277, Lower secondary=3,816, Academic degree=164


**`NAME_FAMILY_STATUS`** (6 levels): Married=196,432, Single / not married=45,444, Civil marriage=29,775, Separated=19,770, Widow=16,088, Unknown=2


**`NAME_HOUSING_TYPE`** (6 levels): House / apartment=272,868, With parents=14,840, Municipal apartment=11,183, Rented apartment=4,881, Office apartment=2,617, Co-op apartment=1,122


**`OCCUPATION_TYPE`** (18 levels): Laborers=55,186, Sales staff=32,102, Core staff=27,570, Managers=21,371, Drivers=18,603, High skill tech staff=11,380, Accountants=9,813, Medicine staff=8,537, Security staff=6,721, Cooking staff=5,946, Cleaning staff=4,653, Private service staff=2,652


**`WEEKDAY_APPR_PROCESS_START`** (7 levels): TUESDAY=53,901, WEDNESDAY=51,934, MONDAY=50,714, THURSDAY=50,591, FRIDAY=50,338, SATURDAY=33,852, SUNDAY=16,181


**`FONDKAPREMONT_MODE`** (4 levels): reg oper account=73,830, reg oper spec account=12,080, not specified=5,687, org spec account=5,619


**`HOUSETYPE_MODE`** (3 levels): block of flats=150,503, specific housing=1,499, terraced house=1,212


**`WALLSMATERIAL_MODE`** (7 levels): Panel=66,040, Stone, brick=64,815, Block=9,253, Wooden=5,362, Mixed=2,296, Monolithic=1,779, Others=1,625


**`EMERGENCYSTATE_MODE`** (2 levels): No=159,428, Yes=2,328


## `bureau.csv` — 1,716,428 rows, 17 columns

| column | dtype | null % | min | max | mean | negatives |
|---|---|---:|---:|---:|---:|---:|
| SK_ID_CURR | int64 | 0.00 | 100,001.00 | 456,255.00 | 278,214.93 |  |
| SK_ID_BUREAU | int64 | 0.00 | 5,000,000.00 | 6,843,457.00 | 5,924,434.49 |  |
| CREDIT_ACTIVE | str | 0.00 | - | - | - |  |
| CREDIT_CURRENCY | str | 0.00 | - | - | - |  |
| DAYS_CREDIT | int64 | 0.00 | -2,922.00 | 0.00 | -1,142.11 | 1,716,403 |
| CREDIT_DAY_OVERDUE | int64 | 0.00 | 0.00 | 2,792.00 | 0.82 |  |
| DAYS_CREDIT_ENDDATE | float64 | 6.15 | -42,060.00 | 31,199.00 | 510.52 | 1,007,389 |
| DAYS_ENDDATE_FACT | float64 | 36.92 | -42,023.00 | 0.00 | -1,017.44 | 1,082,711 |
| AMT_CREDIT_MAX_OVERDUE | float64 | 65.51 | 0.00 | 115,987,185.00 | 3,825.42 |  |
| CNT_CREDIT_PROLONG | int64 | 0.00 | 0.00 | 9.00 | 0.01 |  |
| AMT_CREDIT_SUM | float64 | 0.00 | 0.00 | 585,000,000.00 | 354,994.59 |  |
| AMT_CREDIT_SUM_DEBT | float64 | 15.01 | -4,705,600.32 | 170,100,000.00 | 137,085.12 | 8,418 |
| AMT_CREDIT_SUM_LIMIT | float64 | 34.48 | -586,406.11 | 4,705,600.32 | 6,229.51 | 351 |
| AMT_CREDIT_SUM_OVERDUE | float64 | 0.00 | 0.00 | 3,756,681.00 | 37.91 |  |
| CREDIT_TYPE | str | 0.00 | - | - | - |  |
| DAYS_CREDIT_UPDATE | int64 | 0.00 | -41,947.00 | 372.00 | -593.75 | 1,715,806 |
| AMT_ANNUITY | float64 | 71.47 | 0.00 | 118,453,423.50 | 15,712.76 |  |

**`CREDIT_ACTIVE`** (4 levels): Closed=1,079,273, Active=630,607, Sold=6,527, Bad debt=21


**`CREDIT_CURRENCY`** (4 levels): currency 1=1,715,020, currency 2=1,224, currency 3=174, currency 4=10


**`CREDIT_TYPE`** (15 levels): Consumer credit=1,251,615, Credit card=402,195, Car loan=27,690, Mortgage=18,391, Microloan=12,413, Loan for business development=1,975, Another type of loan=1,017, Unknown type of loan=555, Loan for working capital replenishment=469, Cash loan (non-earmarked)=56, Real estate loan=27, Loan for the purchase of equipment=19


## `bureau_balance.csv` — 27,299,925 rows, 3 columns

| column | dtype | null % | min | max | mean | negatives |
|---|---|---:|---:|---:|---:|---:|
| SK_ID_BUREAU | int64 | 0.00 | 5,001,709.00 | 6,842,888.00 | 6,036,297.33 |  |
| MONTHS_BALANCE | int64 | 0.00 | -96.00 | 0.00 | -30.74 | 26,688,960 |
| STATUS | str | 0.00 | - | - | - |  |

**`STATUS`** (8 levels): C=13,646,993, 0=7,499,507, X=5,810,482, 1=242,347, 5=62,406, 2=23,419, 3=8,924, 4=5,847


## `previous_application.csv` — 1,670,214 rows, 37 columns

| column | dtype | null % | min | max | mean | negatives |
|---|---|---:|---:|---:|---:|---:|
| SK_ID_PREV | int64 | 0.00 | 1,000,001.00 | 2,845,382.00 | 1,923,089.14 |  |
| SK_ID_CURR | int64 | 0.00 | 100,001.00 | 456,255.00 | 278,357.17 |  |
| NAME_CONTRACT_TYPE | str | 0.00 | - | - | - |  |
| AMT_ANNUITY | float64 | 22.29 | 0.00 | 418,058.15 | 15,955.12 |  |
| AMT_APPLICATION | float64 | 0.00 | 0.00 | 6,905,160.00 | 175,233.86 |  |
| AMT_CREDIT | float64 | 0.00 | 0.00 | 6,905,160.00 | 196,114.02 |  |
| AMT_DOWN_PAYMENT | float64 | 53.64 | -0.90 | 3,060,045.00 | 6,697.40 | 2 |
| AMT_GOODS_PRICE | float64 | 23.08 | 0.00 | 6,905,160.00 | 227,847.28 |  |
| WEEKDAY_APPR_PROCESS_START | str | 0.00 | - | - | - |  |
| HOUR_APPR_PROCESS_START | int64 | 0.00 | 0.00 | 23.00 | 12.48 |  |
| FLAG_LAST_APPL_PER_CONTRACT | str | 0.00 | - | - | - |  |
| NFLAG_LAST_APPL_IN_DAY | int64 | 0.00 | 0.00 | 1.00 | 1.00 |  |
| RATE_DOWN_PAYMENT | float64 | 53.64 | -0.00 | 1.00 | 0.08 | 2 |
| RATE_INTEREST_PRIMARY | float64 | 99.64 | 0.03 | 1.00 | 0.19 |  |
| RATE_INTEREST_PRIVILEGED | float64 | 99.64 | 0.37 | 1.00 | 0.77 |  |
| NAME_CASH_LOAN_PURPOSE | str | 0.00 | - | - | - |  |
| NAME_CONTRACT_STATUS | str | 0.00 | - | - | - |  |
| DAYS_DECISION | int64 | 0.00 | -2,922.00 | -1.00 | -880.68 | 1,670,214 |
| NAME_PAYMENT_TYPE | str | 0.00 | - | - | - |  |
| CODE_REJECT_REASON | str | 0.00 | - | - | - |  |
| NAME_TYPE_SUITE | str | 49.12 | - | - | - |  |
| NAME_CLIENT_TYPE | str | 0.00 | - | - | - |  |
| NAME_GOODS_CATEGORY | str | 0.00 | - | - | - |  |
| NAME_PORTFOLIO | str | 0.00 | - | - | - |  |
| NAME_PRODUCT_TYPE | str | 0.00 | - | - | - |  |
| CHANNEL_TYPE | str | 0.00 | - | - | - |  |
| SELLERPLACE_AREA | int64 | 0.00 | -1.00 | 4,000,000.00 | 313.95 | 762,675 |
| NAME_SELLER_INDUSTRY | str | 0.00 | - | - | - |  |
| CNT_PAYMENT | float64 | 22.29 | 0.00 | 84.00 | 16.05 |  |
| NAME_YIELD_GROUP | str | 0.00 | - | - | - |  |
| PRODUCT_COMBINATION | str | 0.02 | - | - | - |  |
| DAYS_FIRST_DRAWING | float64 | 40.30 | -2,922.00 | 365,243.00 | 342,209.86 | 62,705 |
| DAYS_FIRST_DUE | float64 | 40.30 | -2,892.00 | 365,243.00 | 13,826.27 | 956,504 |
| DAYS_LAST_DUE_1ST_VERSION | float64 | 40.30 | -2,801.00 | 365,243.00 | 33,767.77 | 678,188 |
| DAYS_LAST_DUE | float64 | 40.30 | -2,889.00 | 365,243.00 | 76,582.40 | 785,928 |
| DAYS_TERMINATION | float64 | 40.30 | -2,874.00 | 365,243.00 | 81,992.34 | 771,236 |
| NFLAG_INSURED_ON_APPROVAL | float64 | 40.30 | 0.00 | 1.00 | 0.33 |  |

**`NAME_CONTRACT_TYPE`** (4 levels): Cash loans=747,553, Consumer loans=729,151, Revolving loans=193,164, XNA=346


**`WEEKDAY_APPR_PROCESS_START`** (7 levels): TUESDAY=255,118, WEDNESDAY=255,010, MONDAY=253,557, FRIDAY=252,048, THURSDAY=249,099, SATURDAY=240,631, SUNDAY=164,751


**`FLAG_LAST_APPL_PER_CONTRACT`** (2 levels): Y=1,661,739, N=8,475


**`NAME_CASH_LOAN_PURPOSE`** (25 levels): XAP=922,661, XNA=677,918, Repairs=23,765, Other=15,608, Urgent needs=8,412, Buying a used car=2,888, Building a house or an annex=2,693, Everyday expenses=2,416, Medicine=2,174, Payments on other loans=1,931, Education=1,573, Journey=1,239


**`NAME_CONTRACT_STATUS`** (4 levels): Approved=1,036,781, Canceled=316,319, Refused=290,678, Unused offer=26,436


**`NAME_PAYMENT_TYPE`** (4 levels): Cash through the bank=1,033,552, XNA=627,384, Non-cash from your account=8,193, Cashless from the account of the employer=1,085


**`CODE_REJECT_REASON`** (9 levels): XAP=1,353,093, HC=175,231, LIMIT=55,680, SCO=37,467, CLIENT=26,436, SCOFR=12,811, XNA=5,244, VERIF=3,535, SYSTEM=717


**`NAME_TYPE_SUITE`** (7 levels): Unaccompanied=508,970, Family=213,263, Spouse, partner=67,069, Children=31,566, Other_B=17,624, Other_A=9,077, Group of people=2,240


**`NAME_CLIENT_TYPE`** (4 levels): Repeater=1,231,261, New=301,363, Refreshed=135,649, XNA=1,941


**`NAME_PORTFOLIO`** (5 levels): POS=691,011, Cash=461,563, XNA=372,230, Cards=144,985, Cars=425


**`NAME_PRODUCT_TYPE`** (3 levels): XNA=1,063,666, x-sell=456,287, walk-in=150,261


**`CHANNEL_TYPE`** (8 levels): Credit and cash offices=719,968, Country-wide=494,690, Stone=212,083, Regional / Local=108,528, Contact center=71,297, AP+ (Cash loan)=57,046, Channel of corporate sales=6,150, Car dealer=452


**`NAME_SELLER_INDUSTRY`** (11 levels): XNA=855,720, Consumer electronics=398,265, Connectivity=276,029, Furniture=57,849, Construction=29,781, Clothing=23,949, Industry=19,194, Auto technology=4,990, Jewelry=2,709, MLM partners=1,215, Tourism=513


**`NAME_YIELD_GROUP`** (5 levels): XNA=517,215, middle=385,532, high=353,331, low_normal=322,095, low_action=92,041


**`PRODUCT_COMBINATION`** (17 levels): Cash=285,990, POS household with interest=263,622, POS mobile with interest=220,670, Cash X-Sell: middle=143,883, Cash X-Sell: low=130,248, Card Street=112,582, POS industry with interest=98,833, POS household without interest=82,908, Card X-Sell=80,582, Cash Street: high=59,639, Cash X-Sell: high=59,301, Cash Street: middle=34,658


## `POS_CASH_balance.csv` — 10,001,358 rows, 8 columns

| column | dtype | null % | min | max | mean | negatives |
|---|---|---:|---:|---:|---:|---:|
| SK_ID_PREV | int64 | 0.00 | 1,000,001.00 | 2,843,499.00 | 1,903,216.60 |  |
| SK_ID_CURR | int64 | 0.00 | 100,001.00 | 456,255.00 | 278,403.86 |  |
| MONTHS_BALANCE | int64 | 0.00 | -96.00 | -1.00 | -35.01 | 10,001,358 |
| CNT_INSTALMENT | float64 | 0.26 | 1.00 | 92.00 | 17.09 |  |
| CNT_INSTALMENT_FUTURE | float64 | 0.26 | 0.00 | 85.00 | 10.48 |  |
| NAME_CONTRACT_STATUS | str | 0.00 | - | - | - |  |
| SK_DPD | int64 | 0.00 | 0.00 | 4,231.00 | 11.61 |  |
| SK_DPD_DEF | int64 | 0.00 | 0.00 | 3,595.00 | 0.65 |  |

**`NAME_CONTRACT_STATUS`** (9 levels): Active=9,151,119, Completed=744,883, Signed=87,260, Demand=7,065, Returned to the store=5,461, Approved=4,917, Amortized debt=636, Canceled=15, XNA=2


## `credit_card_balance.csv` — 3,840,312 rows, 23 columns

| column | dtype | null % | min | max | mean | negatives |
|---|---|---:|---:|---:|---:|---:|
| SK_ID_PREV | int64 | 0.00 | 1,000,018.00 | 2,843,496.00 | 1,904,503.59 |  |
| SK_ID_CURR | int64 | 0.00 | 100,006.00 | 456,250.00 | 278,324.21 |  |
| MONTHS_BALANCE | int64 | 0.00 | -96.00 | -1.00 | -34.52 | 3,840,312 |
| AMT_BALANCE | float64 | 0.00 | -420,250.18 | 1,505,902.19 | 58,300.16 | 2,345 |
| AMT_CREDIT_LIMIT_ACTUAL | int64 | 0.00 | 0.00 | 1,350,000.00 | 153,807.96 |  |
| AMT_DRAWINGS_ATM_CURRENT | float64 | 19.52 | -6,827.31 | 2,115,000.00 | 5,961.32 | 1 |
| AMT_DRAWINGS_CURRENT | float64 | 0.00 | -6,211.62 | 2,287,098.31 | 7,433.39 | 3 |
| AMT_DRAWINGS_OTHER_CURRENT | float64 | 19.52 | 0.00 | 1,529,847.00 | 288.17 |  |
| AMT_DRAWINGS_POS_CURRENT | float64 | 19.52 | 0.00 | 2,239,274.16 | 2,968.80 |  |
| AMT_INST_MIN_REGULARITY | float64 | 7.95 | 0.00 | 202,882.01 | 3,540.20 |  |
| AMT_PAYMENT_CURRENT | float64 | 20.00 | 0.00 | 4,289,207.45 | 10,280.54 |  |
| AMT_PAYMENT_TOTAL_CURRENT | float64 | 0.00 | 0.00 | 4,278,315.69 | 7,588.86 |  |
| AMT_RECEIVABLE_PRINCIPAL | float64 | 0.00 | -423,305.82 | 1,472,316.79 | 55,965.88 | 2,428 |
| AMT_RECIVABLE | float64 | 0.00 | -420,250.18 | 1,493,338.19 | 58,088.81 | 109,338 |
| AMT_TOTAL_RECEIVABLE | float64 | 0.00 | -420,250.18 | 1,493,338.19 | 58,098.29 | 109,330 |
| CNT_DRAWINGS_ATM_CURRENT | float64 | 19.52 | 0.00 | 51.00 | 0.31 |  |
| CNT_DRAWINGS_CURRENT | int64 | 0.00 | 0.00 | 165.00 | 0.70 |  |
| CNT_DRAWINGS_OTHER_CURRENT | float64 | 19.52 | 0.00 | 12.00 | 0.00 |  |
| CNT_DRAWINGS_POS_CURRENT | float64 | 19.52 | 0.00 | 165.00 | 0.56 |  |
| CNT_INSTALMENT_MATURE_CUM | float64 | 7.95 | 0.00 | 120.00 | 20.83 |  |
| NAME_CONTRACT_STATUS | str | 0.00 | - | - | - |  |
| SK_DPD | int64 | 0.00 | 0.00 | 3,260.00 | 9.28 |  |
| SK_DPD_DEF | int64 | 0.00 | 0.00 | 3,260.00 | 0.33 |  |

**`NAME_CONTRACT_STATUS`** (7 levels): Active=3,698,436, Completed=128,918, Signed=11,058, Demand=1,365, Sent proposal=513, Refused=17, Approved=5


## `installments_payments.csv` — 13,605,401 rows, 8 columns

| column | dtype | null % | min | max | mean | negatives |
|---|---|---:|---:|---:|---:|---:|
| SK_ID_PREV | int64 | 0.00 | 1,000,001.00 | 2,843,499.00 | 1,903,364.97 |  |
| SK_ID_CURR | int64 | 0.00 | 100,001.00 | 456,255.00 | 278,444.88 |  |
| NUM_INSTALMENT_VERSION | float64 | 0.00 | 0.00 | 178.00 | 0.86 |  |
| NUM_INSTALMENT_NUMBER | int64 | 0.00 | 1.00 | 277.00 | 18.87 |  |
| DAYS_INSTALMENT | float64 | 0.00 | -2,922.00 | -1.00 | -1,042.27 | 13,605,401 |
| DAYS_ENTRY_PAYMENT | float64 | 0.02 | -4,921.00 | -1.00 | -1,051.11 | 13,602,496 |
| AMT_INSTALMENT | float64 | 0.00 | 0.00 | 3,771,487.85 | 17,050.91 |  |
| AMT_PAYMENT | float64 | 0.02 | 0.00 | 3,771,487.85 | 17,238.22 |  |