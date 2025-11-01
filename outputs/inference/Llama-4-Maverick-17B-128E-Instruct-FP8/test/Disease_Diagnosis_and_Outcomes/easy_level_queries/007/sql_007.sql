WITH ugib_patients AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10 AND icd_code LIKE 'K92%' AND seq_num = 1
  UNION DISTINCT
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 9 AND (icd_code = '578.0' OR icd_code = '578.1' OR icd_code = '578.9') AND seq_num = 1
),
relevant_admissions AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, 
         DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN ugib_patients u ON a.hadm_id = u.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 84 AND 94
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(los_days, 100)[OFFSET(75)] - APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS iqr
FROM relevant_admissions;