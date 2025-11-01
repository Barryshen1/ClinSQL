WITH 
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age BETWEEN 82 AND 92
    AND gender = 'M'
  ),
  
  digoxin_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN target_patients tp ON p.subject_id = tp.subject_id
    WHERE LOWER(p.drug) LIKE '%digoxin%'
  ),
  
  prescription_durations AS (
    SELECT subject_id, hadm_id, 
           TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration
    FROM digoxin_prescriptions
    WHERE stoptime IS NOT NULL  -- Ensure prescription has an end time
  )

SELECT MAX(duration) AS longest_duration
FROM prescription_durations;