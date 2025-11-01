WITH patient_info AS (
  SELECT 
    p.subject_id,
    p.anchor_age,
    p.gender,
    p.anchor_year
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  WHERE 
    p.gender = 'M' AND 
    p.anchor_age BETWEEN 62 AND 72
),
prescription_counts AS (
  SELECT 
    subject_id,
    COUNT(*) as count
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` 
  WHERE 
    drug LIKE '%amiodarone%'
  GROUP BY 
    subject_id
),
single_prescriptions AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN 
    patient_info p ON pr.subject_id = p.subject_id
  JOIN 
    prescription_counts pc ON pr.subject_id = pc.subject_id
  WHERE 
    pr.drug LIKE '%amiodarone%' AND 
    pr.stoptime IS NOT NULL
    AND pc.count = 1
),
durations_in_days AS (
  SELECT 
    subject_id,
    DATE_DIFF(stoptime, starttime, 'DAY') AS duration_in_days
  FROM 
    single_prescriptions
)
SELECT 
  APPROX_QUANTILES(duration_in_days, 0.25) AS Q1,
  APPROX_QUANTILES(duration_in_days, 0.5) AS median,
  APPROX_QUANTILES(duration_in_days, 0.75) AS Q3,
  APPROX_QUANTILES(duration_in_days, 0.75) - APPROX_QUANTILES(duration_in_days, 0.25) AS IQR
FROM 
  durations_in_days;