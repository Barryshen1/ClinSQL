WITH patient_prescriptions AS (
  SELECT 
    p.subject_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    DATETIME_DIFF(pr.stoptime, pr.starttime, HOUR) AS duration_hours
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.subject_id = pr.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND LOWER(pr.drug) LIKE '%digoxin%'
    AND pr.starttime IS NOT NULL
    AND pr.stoptime IS NOT NULL
),
prescription_durations AS (
  SELECT 
    duration_hours
  FROM 
    patient_prescriptions
  WHERE 
    duration_hours >= 0  
)

SELECT 
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(25)] AS Q1,
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(50)] AS median,
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(75)] AS Q3,
  APPROX_QUANTILES(duration_hours, 100)[OFFSET(75)] - APPROX_QUANTILES(duration_hours, 100)[OFFSET(25)] AS IQR
FROM 
  prescription_durations;