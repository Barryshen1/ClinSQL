WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 81 AND 91
  ),
  
  -- Identify dihydropyridine CCB prescriptions
  ccb_prescriptions AS (
    SELECT p.subject_id, pr.hadm_id, pr.starttime, pr.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN patients_of_interest p ON pr.subject_id = p.subject_id
    WHERE LOWER(pr.drug) LIKE '%dihydropyridine%' OR LOWER(pr.drug) LIKE '%calcium channel blocker%'
  ),
  
  -- Calculate duration of prescriptions
  prescription_durations AS (
    SELECT subject_id, hadm_id, 
           TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
    FROM ccb_prescriptions
    WHERE stoptime IS NOT NULL AND starttime IS NOT NULL
  )

-- Calculate 25th percentile of durations
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) OVER () AS percentile_25_duration
FROM prescription_durations;