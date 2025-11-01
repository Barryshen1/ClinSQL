WITH patient_birth AS (
  SELECT 
    subject_id,
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'  -- filter for male patients here
),
admissions_with_age AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_birth p ON a.subject_id = p.subject_id
),
filtered_admissions AS (
  SELECT *
  FROM admissions_with_age
  WHERE age_at_admission BETWEEN 86 AND 96
),
digoxin_prescriptions AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN filtered_admissions f ON p.subject_id = f.subject_id AND p.hadm_id = f.hadm_id
  WHERE LOWER(p.drug) LIKE '%digoxin%'  -- case-insensitive match
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
)
SELECT 
  quartiles[OFFSET(75)] - quartiles[OFFSET(25)] AS iqr
FROM (
  SELECT APPROX_QUANTILES(duration_days, 100) AS quartiles
  FROM digoxin_prescriptions
);