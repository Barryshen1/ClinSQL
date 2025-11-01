WITH female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 58 AND 68
),
hemorrhagic_stroke_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- ICD-10 hemorrhagic stroke
    (icd_version = 10 AND (
      REGEXP_CONTAINS(icd_code, r'^I60') OR
      REGEXP_CONTAINS(icd_code, r'^I61') OR
      REGEXP_CONTAINS(icd_code, r'^I62')
    ))
    -- ICD-9 hemorrhagic stroke
    OR (icd_version = 9 AND (
      icd_code = '430' OR
      icd_code = '431' OR
      REGEXP_CONTAINS(icd_code, r'^432')
    ))
  )
),
copd_exacerbation_admissions AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (
    -- ICD-10 COPD exacerbation
    (icd_version = 10 AND (
      icd_code = 'J44.1' OR
      icd_code = 'J44.0'
    ))
    -- ICD-9 COPD exacerbation
    OR (icd_version = 9 AND (
      icd_code = '491.21' OR
      icd_code = '492.8' OR
      icd_code = '496'
    ))
  )
),
target_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN female_patients p ON a.subject_id = p.subject_id
  INNER JOIN hemorrhagic_stroke_admissions hs ON a.hadm_id = hs.hadm_id
  INNER JOIN copd_exacerbation_admissions copd ON a.hadm_id = copd.hadm_id
  WHERE a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
SELECT
  quantiles[OFFSET(1)] AS los_25th_percentile_days,
  quantiles[OFFSET(3)] AS los_75th_percentile_days,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS los_iqr_days
FROM (
  SELECT
    APPROX_QUANTILES(
      SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400), 4
    ) AS quantiles
  FROM target_admissions
  WHERE SAFE_DIVIDE(TIMESTAMP_DIFF(dischtime, admittime, SECOND), 86400) > 0
);