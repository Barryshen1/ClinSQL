WITH patient_age AS (
  SELECT p.subject_id, 
         p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
relevant_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_age pa ON a.subject_id = pa.subject_id
  WHERE pa.age_at_admission BETWEEN 36 AND 46
),
digoxin_prescriptions AS (
  SELECT p.hadm_id, 
         p.starttime, 
         p.stoptime, 
         DATETIME_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN relevant_admissions ra ON p.hadm_id = ra.hadm_id
  WHERE LOWER(p.drug) LIKE '%digoxin%'
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_days, 100)[OFFSET(25)] AS iqr
FROM digoxin_prescriptions;