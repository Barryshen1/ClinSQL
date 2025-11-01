WITH filtered_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 59 AND 69
),
relevant_prescriptions AS (
  SELECT p.subject_id, p.starttime, p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN filtered_patients fp ON p.subject_id = fp.subject_id
  WHERE LOWER(p.drug) LIKE '%amlodipine%' OR LOWER(p.drug) LIKE '%nifedipine%' 
    OR LOWER(p.drug) LIKE '%nicardipine%' OR LOWER(p.drug) LIKE '%isradipine%' 
    OR LOWER(p.drug) LIKE '%felodipine%' OR LOWER(p.drug) LIKE '%nisoldipine%' 
    OR LOWER(p.drug) LIKE '%nimodipine%'
),
prescription_durations AS (
  SELECT subject_id, DATETIME_DIFF(stoptime, starttime, MINUTE) AS duration_minutes
  FROM relevant_prescriptions
  WHERE stoptime IS NOT NULL AND starttime IS NOT NULL
)
SELECT APPROX_QUANTILES(duration_minutes, 2)[OFFSET(1)] AS median_duration_minutes
FROM prescription_durations;