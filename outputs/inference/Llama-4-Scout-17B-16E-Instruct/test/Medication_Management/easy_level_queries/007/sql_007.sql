WITH 
  -- Filter patients and prescriptions
  eligible_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'F' AND anchor_age BETWEEN 90 AND 100
  ),
  thiazide_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN eligible_patients ep ON p.subject_id = ep.subject_id
    WHERE LOWER(p.drug) LIKE '%thiazide%' 
      OR LOWER(p.drug) LIKE '%chlorthalidone%' 
      OR LOWER(p.drug) LIKE '%hydrochlorothiazide%' 
      OR LOWER(p.drug) LIKE '%metolazone%'
  ),
  prescription_durations AS (
    SELECT 
      subject_id,
      hadm_id,
      TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
    FROM thiazide_prescriptions
    WHERE stoptime IS NOT NULL AND starttime IS NOT NULL
  )

-- Calculate IQR of prescription durations
SELECT 
  PERCENTILE_CONT(0.75) OVER (ORDER BY duration_days) - 
  PERCENTILE_CONT(0.25) OVER (ORDER BY duration_days) AS iqr_days
FROM prescription_durations;