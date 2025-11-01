WITH 
  -- Filter patients and prescriptions
  patient_data AS (
    SELECT p.subject_id, p.anchor_age, p.gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE p.gender = 'F' AND p.anchor_age BETWEEN 59 AND 69
  ),
  
  amiodarone_prescriptions AS (
    SELECT p.subject_id, pr.starttime, pr.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN patient_data p ON pr.subject_id = p.subject_id
    WHERE LOWER(pr.drug) LIKE '%amiodarone%'
  ),
  
  -- Calculate prescription durations in days
  prescription_durations AS (
    SELECT 
      subject_id,
      CAST(EXTRACT(DAY FROM (DATE(stoptime) - DATE(starttime))) AS INT64) AS duration_days
    FROM amiodarone_prescriptions
    WHERE stoptime IS NOT NULL AND starttime IS NOT NULL
  )

-- Calculate IQR of prescription durations
SELECT 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(0)] AS Q1,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS median,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(2)] AS Q3,
  APPROX_QUANTILES(duration_days, 4)[OFFSET(2)] - 
  APPROX_QUANTILES(duration_days, 4)[OFFSET(0)] AS IQR
FROM prescription_durations;