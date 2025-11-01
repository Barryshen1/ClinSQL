WITH 
  -- Filter patients by age and gender
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 36 AND 46
  ),
  
  -- Filter prescriptions for digoxin and calculate duration
  digoxin_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime,
           DATE_DIFF(p.stoptime, p.starttime, 'DAY') AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN eligible_patients ep ON p.subject_id = ep.subject_id
    WHERE LOWER(p.drug) LIKE '%digoxin%'
    AND p.stoptime IS NOT NULL  -- Ensure we have a valid duration
  )

-- Calculate IQR of prescription durations
SELECT 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS Q1,
  APPROX_QUANTILES(duration_days, 0.5)[OFFSET(0)] AS median,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] AS Q3,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] - 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS IQR
FROM digoxin_prescriptions;