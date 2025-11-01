WITH patient_prescriptions AS (
  SELECT 
    p.subject_id,
    pr.drug,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) / 24 AS duration_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 58 AND 68
    AND (LOWER(pr.drug) LIKE '%heparin%' OR LOWER(pr.drug) LIKE '%enoxaparin%')
),
filtered_durations AS (
  SELECT 
    duration_days
  FROM 
    patient_prescriptions
  WHERE 
    duration_days > 0  -- exclude invalid or missing durations
)
SELECT 
  APPROX_QUANTILES(duration_days, 100)[OFFSET(50)] AS median_duration_days
FROM 
  filtered_durations;