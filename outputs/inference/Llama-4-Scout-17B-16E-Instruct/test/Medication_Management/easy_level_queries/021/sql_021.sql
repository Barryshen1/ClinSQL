WITH 
  -- Filter patients and prescriptions of interest
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 75 AND 85
  ),
  
  atorvastatin_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime, 
           SAFE_CAST(p.dose_val_rx AS INT64) AS dose_val_rx
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN eligible_patients ep ON p.subject_id = ep.subject_id
    WHERE p.drug LIKE '%Atorvastatin%' 
      AND (SAFE_CAST(p.dose_val_rx AS INT64) BETWEEN 40 AND 80 
           OR p.form_val_disp IN ('40 mg', '80 mg'))
  ),
  
  -- Calculate duration for each prescription
  prescription_durations AS (
    SELECT subject_id, hadm_id, 
           TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
    FROM atorvastatin_prescriptions
    WHERE starttime IS NOT NULL AND stoptime IS NOT NULL
  )

-- Calculate IQR of durations
SELECT 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS Q1,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] AS Q3,
  APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] - 
  APPROX_QUANTILES(duration_days, 0.25)[OFFSET(0)] AS IQR
FROM prescription_durations;