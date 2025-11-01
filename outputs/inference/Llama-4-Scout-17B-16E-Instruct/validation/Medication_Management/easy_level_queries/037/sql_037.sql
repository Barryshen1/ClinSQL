WITH 
  -- Filter patients of interest and relevant prescriptions
  patients_of_interest AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE anchor_age = 55 AND gender = 'F'
  ),
  ace_inhibitor_prescriptions AS (
    SELECT p.subject_id, p.hadm_id, p.starttime, p.stoptime
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    JOIN patients_of_interest poi ON p.subject_id = poi.subject_id
    WHERE LOWER(p.drug) LIKE '%ace inhibitor%' OR LOWER(p.drug) LIKE '%lisinopril%' OR LOWER(p.drug) LIKE '%enalapril%' 
      OR LOWER(p.drug) LIKE '%captopril%' OR LOWER(p.drug) LIKE '%ramipril%' OR LOWER(p.drug) LIKE '%quinapril%'
  ),
  prescription_durations AS (
    SELECT subject_id, hadm_id, 
           TIMESTAMP_DIFF(stoptime, starttime, DAY) AS prescription_duration
    FROM ace_inhibitor_prescriptions
    WHERE stoptime IS NOT NULL  -- Ensure we have a valid duration
  )

-- Calculate 25th percentile of prescription durations
SELECT APPROX_QUANTILES(prescription_duration, 25) WITHIN RECORD AS percentile_25_duration
FROM prescription_durations;