WITH 
-- Filter patients of interest and prescriptions
patients_of_interest AS (
  SELECT subject_id, anchor_age, gender, dod
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_age BETWEEN 76 AND 86 AND gender = 'M'
),
prescriptions_of_interest AS (
  SELECT p.subject_id, pr.starttime, pr.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  JOIN patients_of_interest p ON pr.subject_id = p.subject_id
  WHERE LOWER(pr.drug) LIKE '%nitrate%' 
    AND pr.route IN ('IV', 'PO')  -- Assuming IV or oral (PO) routes
    AND pr.starttime IS NOT NULL AND pr.stoptime IS NOT NULL
),
-- Calculate duration of prescriptions
prescription_durations AS (
  SELECT subject_id, 
         TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
  FROM prescriptions_of_interest
)
-- Calculate 25th percentile of duration
SELECT 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY duration_days) AS percentile_25_duration
FROM prescription_durations;