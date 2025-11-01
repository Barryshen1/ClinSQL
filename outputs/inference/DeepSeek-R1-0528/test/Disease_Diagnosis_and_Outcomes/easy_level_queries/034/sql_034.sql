WITH sepsis_admissions AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    seq_num = 1  -- Primary diagnosis
    AND (
      (icd_version = 9 AND (icd_code LIKE '038%' OR icd_code = '78552'))
      OR 
      (icd_version = 10 AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%' OR icd_code IN ('R6520', 'R6521')))
    )
)

SELECT 
  APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS q1,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS q3,
  APPROX_QUANTILES(los_days, 4)[OFFSET(3)] - APPROX_QUANTILES(los_days, 4)[OFFSET(1)] AS iqr
FROM (
  SELECT 
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN sepsis_admissions s 
    ON a.subject_id = s.subject_id AND a.hadm_id = s.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 40 AND 50
);