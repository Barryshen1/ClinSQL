WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age >= 69
    AND anchor_age <= 79
),
ugib_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (
    SUBSTR(icd_code, 1, 3) IN ('K25', 'K26', 'K27', 'K28') -- peptic ulcer with hemorrhage
    OR icd_code IN ('K920', 'K921', 'K922') -- hematemesis, melena, GI bleed
  )
  AND icd_version = 10
),
copd_exac_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE icd_code = 'J441' AND icd_version = 10
),
admissions_with_ugib AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN ugib_codes u ON di.icd_code = u.icd_code AND di.icd_version = 10
),
admissions_with_copd_exac AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN copd_exac_codes c ON di.icd_code = c.icd_code AND di.icd_version = 10
),
qualifying_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN filtered_patients fp ON a.subject_id = fp.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM admissions_with_ugib)
    AND a.hadm_id IN (SELECT hadm_id FROM admissions_with_copd_exac)
),
los_calc AS (
  SELECT 
    hadm_id,
    DATETIME_DIFF(dischtime, admittime, SECOND) / (24 * 60 * 60) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
  WHERE hadm_id IN (SELECT hadm_id FROM qualifying_admissions)
    AND dischtime IS NOT NULL
    AND admittime IS NOT NULL
)
SELECT
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los_days
FROM los_calc;