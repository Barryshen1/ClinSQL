WITH 
  -- Filter patients of interest
  patients_of_interest AS (
    SELECT subject_id, anchor_age, gender
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 78 AND 88
  ),

  -- Identify ACE-inhibitor prescriptions and calculate duration
  ace_inhibitor_prescriptions AS (
    SELECT p.subject_id, pr.starttime, pr.stoptime,
           DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN patients_of_interest p ON pr.subject_id = p.subject_id
    WHERE LOWER(pr.drug) LIKE '%ace%' OR LOWER(pr.drug) LIKE '%angiotensin%'
    AND pr.stoptime IS NOT NULL AND pr.starttime IS NOT NULL
  )

-- Calculate standard deviation of prescription durations
SELECT 
  STDEV(duration_days) AS sd_duration_days
FROM ace_inhibitor_prescriptions;