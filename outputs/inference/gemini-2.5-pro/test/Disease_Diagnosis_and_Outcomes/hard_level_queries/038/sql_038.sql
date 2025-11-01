WITH
-- Step 1: Define the base cohort of male patients aged 74-84
base_admissions AS (
  SELECT
    p.subject_id,
    p.dod,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
    ON p.subject_id = adm.subject_id
  WHERE
    p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 74 AND 84
),

-- Step 2: Calculate the Charlson Comorbidity Index from scratch
charlson_components AS (
  SELECT
    diag.hadm_id,
    MAX(CASE WHEN diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) IN ('410', '412') THEN 1 WHEN diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('I21', 'I22') THEN 1 WHEN diag.icd_version = 10 AND diag.icd_code = 'I252' THEN 1 ELSE 0 END) AS myocardial_infarction,
    MAX(CASE WHEN diag.icd_version = 9 AND (diag.icd_code IN ('39891', '40201', '40211', '40291', '40401', '40403', '40411', '40413', '40491', '40493') OR SUBSTR(diag.icd_code, 1, 3) = '428' OR SUBSTR(diag.icd_code, 1, 4) IN ('4254', '4255', '4256', '4257', '4258', '4259')) THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('I099', 'I110', 'I130', 'I132', 'I255', 'I420', 'I425', 'I426', 'I427', 'I428', 'I429', 'I43', 'P290') OR SUBSTR(diag.icd_code, 1, 3) = 'I50') THEN 1 ELSE 0 END) AS congestive_heart_failure,
    MAX(CASE WHEN diag.icd_version = 9 AND (diag.icd_code IN ('0930', '4431', '4432', '4438', '4439', '4471', '5571', '5579', 'V434') OR SUBSTR(diag.icd_code, 1, 3) IN ('440', '441')) THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('I731', 'I738', 'I739', 'I771', 'I790', 'I792', 'K551', 'K558', 'K559', 'Z958', 'Z959') OR SUBSTR(diag.icd_code, 1, 3) IN ('I70', 'I71')) THEN 1 ELSE 0 END) AS peripheral_vascular_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND (diag.icd_code = '36234' OR SUBSTR(diag.icd_code, 1, 3) BETWEEN '430' AND '438') THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('H340', 'H341', 'H342') OR SUBSTR(diag.icd_code, 1, 3) IN ('G45', 'G46') OR SUBSTR(diag.icd_code, 1, 3) BETWEEN 'I60' AND 'I69') THEN 1 ELSE 0 END) AS cerebrovascular_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND diag.icd_code IN ('290', '2941', '3312') THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('F051', 'G30', 'G311') OR SUBSTR(diag.icd_code, 1, 3) IN ('F00', 'F01', 'F02', 'F03')) THEN 1 ELSE 0 END) AS dementia,
    MAX(CASE WHEN diag.icd_version = 9 AND (diag.icd_code IN ('4168', '4169', '5064', '5081', '5088') OR SUBSTR(diag.icd_code, 1, 3) BETWEEN '490' AND '505') THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('I278', 'I279', 'J684', 'J701', 'J703') OR SUBSTR(diag.icd_code, 1, 3) BETWEEN 'J40' AND 'J47' OR SUBSTR(diag.icd_code, 1, 3) BETWEEN 'J60' AND 'J67') THEN 1 ELSE 0 END) AS chronic_pulmonary_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND diag.icd_code IN ('4465', '7100', '7101', '7102', '7103', '7104', '7140', '7141', '7142', '7148', '725') THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('M315', 'M351', 'M353', 'M360') OR SUBSTR(diag.icd_code, 1, 3) IN ('M05', 'M06', 'M32', 'M33', 'M34')) THEN 1 ELSE 0 END) AS rheumatic_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) BETWEEN '531' AND '534' THEN 1 WHEN diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) BETWEEN 'K25' AND 'K28' THEN 1 ELSE 0 END) AS peptic_ulcer_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND diag.icd_code IN ('5712', '5714', '5715', '5716', '5733', '5734', '5738', '5739', 'V427') THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('K700', 'K701', 'K702', 'K703', 'K709', 'K713', 'K714', 'K715', 'K717', 'K73', 'K74', 'K760', 'K762', 'K763', 'K764', 'K768', 'K769', 'Z944') OR SUBSTR(diag.icd_code, 1, 3) = 'B18') THEN 1 ELSE 0 END) AS mild_liver_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 4) IN ('2500', '2501', '2502', '2503', '2508', '2509') THEN 1 WHEN diag.icd_version = 10 AND diag.icd_code IN ('E100', 'E101', 'E106', 'E108', 'E109', 'E110', 'E111', 'E116', 'E118', 'E119', 'E120', 'E121', 'E126', 'E128', 'E129', 'E130', 'E131', 'E136', 'E138', 'E139', 'E140', 'E141', 'E146', 'E148', 'E149') THEN 1 ELSE 0 END) AS diabetes_without_cc,
    MAX(CASE WHEN diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 4) IN ('2504', '2505', '2506', '2507') THEN 1 WHEN diag.icd_version = 10 AND diag.icd_code IN ('E102', 'E103', 'E104', 'E105', 'E107', 'E112', 'E113', 'E114', 'E115', 'E117', 'E122', 'E123', 'E124', 'E125', 'E127', 'E132', 'E133', 'E134', 'E135', 'E137', 'E142', 'E143', 'E144', 'E145', 'E147') THEN 1 ELSE 0 END) AS diabetes_with_cc,
    MAX(CASE WHEN diag.icd_version = 9 AND (diag.icd_code IN ('3341', '3440', '3441', '3442', '3443', '3444', '3445', '3446', '3449') OR SUBSTR(diag.icd_code, 1, 3) IN ('342', '343')) THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('G041', 'G114', 'G801', 'G802', 'G830', 'G831', 'G832', 'G833', 'G834', 'G839') OR SUBSTR(diag.icd_code, 1, 3) IN ('G81', 'G82')) THEN 1 ELSE 0 END) AS paraplegia,
    MAX(CASE WHEN diag.icd_version = 9 AND (diag.icd_code IN ('40301', '40311', '40391', '40402', '40403', '40412', '40413', '40492', '40493', '585', '586', 'V420', 'V451', 'V56') OR SUBSTR(diag.icd_code, 1, 3) IN ('582', '588') OR SUBSTR(diag.icd_code, 1, 4) IN ('5830', '5831', '5832', '5833', '5834', '5835', '5836', '5837')) THEN 1 WHEN diag.icd_version = 10 AND (diag.icd_code IN ('I120', 'I131', 'N19', 'N250', 'Z490', 'Z491', 'Z492', 'Z940', 'Z992') OR SUBSTR(diag.icd_code, 1, 3) = 'N18' OR SUBSTR(diag.icd_code, 1, 4) IN ('N032', 'N033', 'N034', 'N035', 'N036', 'N037', 'N052', 'N053', 'N054', 'N055', 'N056', 'N057')) THEN 1 ELSE 0 END) AS renal_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND (SUBSTR(diag.icd_code, 1, 3) BETWEEN '140' AND '172' OR SUBSTR(diag.icd_code, 1, 4) BETWEEN '1740' AND '1958' OR SUBSTR(diag.icd_code, 1, 3) BETWEEN '200' AND '208' OR diag.icd_code = '2386') THEN 1 WHEN diag.icd_version = 10 AND (SUBSTR(diag.icd_code, 1, 3) BETWEEN 'C00' AND 'C26' OR SUBSTR(diag.icd_code, 1, 3) BETWEEN 'C30' AND 'C41' OR SUBSTR(diag.icd_code, 1, 3) IN ('C43', 'C44') OR SUBSTR(diag.icd_code, 1, 3) BETWEEN 'C45' AND 'C58' OR SUBSTR(diag.icd_code, 1, 3) BETWEEN 'C60' AND 'C76' OR SUBSTR(diag.icd_code, 1, 3) BETWEEN 'C81' AND 'C85' OR SUBSTR(diag.icd_code, 1, 3) IN ('C88', 'C90', 'C91', 'C92', 'C93', 'C94', 'C95', 'C96', 'C97')) THEN 1 ELSE 0 END) AS malignant_cancer,
    MAX(CASE WHEN diag.icd_version = 9 AND (diag.icd_code IN ('4560', '4561', '4562') OR SUBSTR(diag.icd_code, 1, 4) IN ('5722', '5723', '5724', '5728')) THEN 1 WHEN diag.icd_version = 10 AND diag.icd_code IN ('I850', 'I859', 'I864', 'I982', 'K704', 'K711', 'K72', 'K765', 'K766', 'K767') THEN 1 ELSE 0 END) AS severe_liver_disease,
    MAX(CASE WHEN diag.icd_version = 9 AND SUBSTR(diag.icd_code, 1, 3) IN ('196', '197', '198', '199') THEN 1 WHEN diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('C77', 'C78', 'C79', 'C80') THEN 1 ELSE 0 END) AS metastatic_solid_tumor,
    MAX(CASE WHEN diag.icd_version = 9 AND diag.icd_code = '042' THEN 1 WHEN diag.icd_version = 10 AND SUBSTR(diag.icd_code, 1, 3) IN ('B20', 'B21', 'B22', 'B24') THEN 1 ELSE 0 END) AS aids
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS diag
  GROUP BY diag.hadm_id
),
charlson_score AS (
  SELECT
    hadm_id,
    -- FIX: Cast the final score to FLOAT64 to prevent type errors in FORMAT()
    CAST(
        (myocardial_infarction + congestive_heart_failure + peripheral_vascular_disease + cerebrovascular_disease + dementia + chronic_pulmonary_disease + rheumatic_disease + peptic_ulcer_disease)
        + (CASE WHEN diabetes_with_cc = 1 THEN 2 WHEN diabetes_without_cc = 1 THEN 1 ELSE 0 END)
        + (paraplegia * 2)
        + (renal_disease * 2)
        + (CASE WHEN severe_liver_disease = 1 THEN 3 WHEN mild_liver_disease = 1 THEN 1 ELSE 0 END)
        + (CASE WHEN metastatic_solid_tumor = 1 THEN 6 WHEN malignant_cancer = 1 THEN 2 ELSE 0 END)
        + (aids * 6)
    AS FLOAT64) AS score
  FROM charlson_components
),

-- Step 3: Identify admissions with AKI and ARDS diagnoses using specific ICD codes
aki_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 codes for Acute Renal Failure
    (icd_version = 9 AND SUBSTR(icd_code, 1, 3) = '584') OR
    -- ICD-10 codes for Acute Kidney Injury
    (icd_version = 10 AND SUBSTR(icd_code, 1, 3) = 'N17')
),
ards_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    -- ICD-9 code for ARDS
    (icd_version = 9 AND icd_code = '51882') OR
    -- ICD-10 code for ARDS
    (icd_version = 10 AND icd_code = 'J80')
),

-- Step 4: Integrate all data for the cohorts
cohort_details AS (
  SELECT
    b.hadm_id,
    IF(a.hadm_id IS NOT NULL, 1, 0) AS is_aki,
    IF(ar.hadm_id IS NOT NULL, 1, 0) AS is_ards,
    COALESCE(cs.score, 0) AS charlson_score,
    IF(b.hospital_expire_flag = 1, 0, 1) AS is_survivor,
    DATETIME_DIFF(b.dischtime, b.admittime, HOUR) / 24.0 AS los_days,
    IF(b.dod IS NOT NULL AND DATE_DIFF(DATE(b.dod), DATE(b.admittime), DAY) <= 30, 1, 0) AS thirty_day_mortality
  FROM base_admissions AS b
  LEFT JOIN aki_hadms AS a ON b.hadm_id = a.hadm_id
  LEFT JOIN ards_hadms AS ar ON b.hadm_id = ar.hadm_id
  LEFT JOIN charlson_score AS cs ON b.hadm_id = cs.hadm_id
),

-- Step 5: Calculate statistics for each cohort
aki_cohort_stats AS (
  SELECT
    APPROX_QUANTILES(charlson_score, 4) AS charlson_quantiles,
    AVG(thirty_day_mortality) AS mortality_30_day_rate,
    AVG(is_ards) AS ards_rate,
    AVG(CASE WHEN is_survivor = 1 THEN los_days ELSE NULL END) AS survivor_los_days
  FROM cohort_details
  WHERE is_aki = 1
),
general_cohort_stats AS (
  SELECT
    AVG(is_ards) AS ards_rate,
    AVG(CASE WHEN is_survivor = 1 THEN los_days ELSE NULL END) AS survivor_los_days
  FROM cohort_details
),
-- Calculate risk percentiles for the AKI cohort
aki_percentiles AS (
  SELECT
    CONCAT(
        'P75 Score: ', FORMAT('%.1f', p[OFFSET(75)]),
        ', P90 Score: ', FORMAT('%.1f', p[OFFSET(90)]),
        ', P95 Score: ', FORMAT('%.1f', p[OFFSET(95)])
    ) AS risk_percentiles_str
  FROM (
    SELECT APPROX_QUANTILES(charlson_score, 100) AS p
    FROM cohort_details
    WHERE is_aki = 1
  )
)

-- Step 6: Format and present the final results
SELECT
  'AKI Cohort (Male, 74-84)' AS cohort,
  CONCAT(
    FORMAT('%.1f', aki.charlson_quantiles[OFFSET(2)]), ' (',
    FORMAT('%.1f', aki.charlson_quantiles[OFFSET(1)]), ' - ',
    FORMAT('%.1f', aki.charlson_quantiles[OFFSET(3)]), ')'
  ) AS median_charlson_score_iqr,
  aki.mortality_30_day_rate,
  aki.ards_rate,
  aki.survivor_los_days,
  (SELECT risk_percentiles_str FROM aki_percentiles) AS risk_percentiles_aki_cohort
FROM aki_cohort_stats AS aki
UNION ALL
SELECT
  'General Cohort (Male, 74-84)' AS cohort,
  NULL AS median_charlson_score_iqr,
  NULL AS mortality_30_day_rate,
  gen.ards_rate,
  gen.survivor_los_days,
  NULL AS risk_percentiles_aki_cohort
FROM general_cohort_stats AS gen;