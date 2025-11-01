WITH eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 51 AND 61
),
target_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    -- Calculate duration in days, add 1 to include both start and stop dates
    SAFE_CAST(DATE_DIFF(DATE(p.stoptime), DATE(p.starttime), DAY) + 1 AS INT64) AS duration_days
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN eligible_patients ep ON p.subject_id = ep.subject_id
  WHERE
    LOWER(p.drug) LIKE '%hydralazine%'
    OR LOWER(p.drug) LIKE '%isosorbide%'
    OR LOWER(p.drug) LIKE '%dinitrate%'
    -- Exclude records with missing start or stop times
    AND p.starttime IS NOT NULL
    AND p.stoptime IS NOT NULL
)
SELECT
  subject_id,
  drug,
  starttime,
  stoptime,
  duration_days
FROM target_prescriptions
WHERE duration_days = (
  SELECT MAX(duration_days) FROM target_prescriptions
)
ORDER BY subject_id, drug, starttime;