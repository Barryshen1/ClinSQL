WITH 
  -- Filter patients to only include females aged 80–90
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 80 AND 90
  ),

  -- Filter prescriptions to only include IV/oral/sublingual nitrate prescriptions
  nitrate_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN target_patients tp ON p.subject_id = tp.subject_id
    WHERE LOWER(p.drug) LIKE '%nitrate%' AND p.route IN ('IV', 'oral', 'sublingual')
  )

-- Calculate the maximum duration of a single prescription
SELECT 
  MAX(TIMESTAMP_DIFF(stoptime, starttime, DAY)) AS max_duration_days
FROM nitrate_prescriptions;