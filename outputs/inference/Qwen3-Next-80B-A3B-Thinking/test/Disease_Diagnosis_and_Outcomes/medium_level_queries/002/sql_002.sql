WITH ami_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'I21%')
     OR (icd_version = 9 AND icd_code LIKE '410%')
),

shock_respiratory AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND icd_code LIKE 'R57%')
    OR (icd_version = 9 AND icd_code = '785.5')
    OR (icd_version = 10 AND icd_code LIKE 'J96%')
    OR (icd_version = 9 AND icd_code = '518.81')
),

ckd_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'N18%')
     OR (icd_version = 9 AND icd_code LIKE '585%')
),

diabetes_diagnoses AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%'))
     OR (icd_version = 9 AND icd_code LIKE '250%')
),

main_population AS (
  SELECT
    a.hadm_id,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    CASE WHEN ckd.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_ckd,
    CASE WHEN diabetes.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS has_diabetes,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ami_admissions am
    ON a.hadm_id = am.hadm_id
  LEFT JOIN shock_respiratory sr
    ON a.hadm_id = sr.hadm_id
  LEFT JOIN ckd_diagnoses ckd
    ON a.hadm_id = ckd.hadm_id
  LEFT JOIN diabetes_diagnoses diabetes
    ON a.hadm_id = diabetes.hadm_id
  WHERE
    sr.hadm_id IS NULL
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 62 AND 72
),

los_groups AS (
  SELECT
    CASE WHEN los <= 5 THEN 'los_leq5' ELSE 'los_gt5' END AS los_group,
    hospital_expire_flag,
    has_ckd,
    has_diabetes
  FROM main_population
),

mortality_rates AS (
  SELECT
    los_group,
    AVG(hospital_expire_flag) AS mortality_rate,
    AVG(has_ckd) AS ckd_prevalence,
    AVG(has_diabetes) AS diabetes_prevalence
  FROM los_groups
  GROUP BY los_group
)

SELECT
  MAX(CASE WHEN los_group = 'los_leq5' THEN mortality_rate END) AS mortality_rate_leq5,
  MAX(CASE WHEN los_group = 'los_gt5' THEN mortality_rate END) AS mortality_rate_gt5,
  MAX(CASE WHEN los_group = 'los_leq5' THEN mortality_rate END) - 
  MAX(CASE WHEN los_group = 'los_gt5' THEN mortality_rate END) AS abs_mortality_diff,
  (MAX(CASE WHEN los_group = 'los_leq5' THEN mortality_rate END) - 
   MAX(CASE WHEN los_group = 'los_gt5' THEN mortality_rate END)) / 
  NULLIF(MAX(CASE WHEN los_group = 'los_gt5' THEN mortality_rate END), 0) AS rel_mortality_diff,
  MAX(CASE WHEN los_group = 'los_leq5' THEN ckd_prevalence END) AS ckd_prevalence_leq5,
  MAX(CASE WHEN los_group = 'los_gt5' THEN ckd_prevalence END) AS ckd_prevalence_gt5,
  MAX(CASE WHEN los_group = 'los_leq5' THEN diabetes_prevalence END) AS diabetes_prevalence_leq5,
  MAX(CASE WHEN los_group = 'los_gt5' THEN diabetes_prevalence END) AS diabetes_prevalence_gt5
FROM mortality_rates;