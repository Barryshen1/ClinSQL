WITH 
  -- Select relevant patients
  target_patients AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 38 AND 48
  ),
  
  -- Select ARB prescriptions for these patients
  arb_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN target_patients tp ON p.subject_id = tp.subject_id
    WHERE LOWER(p.drug) LIKE '%angiotensin%' OR LOWER(p.drug) LIKE '%losartan%' OR LOWER(p.drug) LIKE '%valsartan%' 
      OR LOWER(p.drug) LIKE '%candesartan%' OR LOWER(p.drug) LIKE '%eprosartan%' OR LOWER(p.drug) LIKE '%irbesartan%' 
      OR LOWER(p.drug) LIKE '%telmisartan%' OR LOWER(p.drug) LIKE '%olmesartan%'
      AND p.stoptime IS NOT NULL
  ),
  
  -- Calculate duration for each prescription
  prescription_durations AS (
    SELECT hadm_id, 
           TIMESTAMP_DIFF(stoptime, starttime, DAY) AS duration_days
    FROM arb_prescriptions
  )

-- Calculate 75th percentile of durations
SELECT APPROX_QUANTILES(duration_days, 0.75)[OFFSET(0)] AS percentile_75
FROM prescription_durations;