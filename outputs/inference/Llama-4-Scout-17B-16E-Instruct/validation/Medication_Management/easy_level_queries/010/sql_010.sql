WITH 
-- Filter patients of interest
patients_of_interest AS (
  SELECT subject_id, anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 73 AND 83
),

-- Identify nitrate prescriptions and calculate their duration
nitrate_prescriptions AS (
  SELECT p.subject_id, 
         pr.starttime, 
         pr.stoptime,
         TIMESTAMP_DIFF(pr.stoptime, pr.starttime, 'DAY') AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN patients_of_interest p ON pr.subject_id = p.subject_id
  WHERE LOWER(pr.drug) LIKE '%nitrate%' AND pr.stoptime IS NOT NULL
)

-- Calculate the standard deviation of prescription durations
SELECT 
  STDEV(duration_days) AS sd_duration_days
FROM 
  nitrate_prescriptions;