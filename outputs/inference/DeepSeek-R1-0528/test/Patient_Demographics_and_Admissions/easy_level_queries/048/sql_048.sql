WITH first_admissions AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.admittime = (
      SELECT MIN(admittime)
      FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
      WHERE a2.subject_id = p.subject_id
    )
),
heart_failure_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '428%') 
    OR (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort AS (
  SELECT f.*
  FROM first_admissions f
  INNER JOIN heart_failure_admissions hf
    ON f.subject_id = hf.subject_id 
    AND f.hadm_id = hf.hadm_id
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr_los_days
FROM cohort;