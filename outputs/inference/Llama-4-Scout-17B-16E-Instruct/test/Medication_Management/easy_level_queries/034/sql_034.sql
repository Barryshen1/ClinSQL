WITH 
  -- Filter patients who are female and between 51-61 years old, and specifically our 56-year-old patient
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 51 AND 61
      AND subject_id IN (SELECT subject_id FROM `physionet-data.mimiciv_3_1_hosp.admissions` WHERE admittime IS NOT NULL)
      AND anchor_age = 56  -- Filter for the 56-year-old patient
  ),

  -- Filter prescriptions for hydralazine or isosorbide dinitrate
  target_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    WHERE (p.drug LIKE '%hydralazine%' OR p.drug LIKE '%isosorbide dinitrate%')
    AND p.subject_id IN (SELECT subject_id FROM target_patients)
  )

-- Calculate the duration of each prescription and find the longest one
SELECT 
  subject_id,
  MAX(duration_days) AS longest_duration_days
FROM 
  (
    SELECT 
      subject_id,
      hadm_id,
      DATE_DIFF(stoptime, starttime, DAY) AS duration_days
    FROM 
      target_prescriptions
  ) AS prescription_durations
GROUP BY 
  subject_id
ORDER BY 
  longest_duration_days DESC
LIMIT 1;