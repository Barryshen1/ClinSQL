WITH relevant_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` AS p
  WHERE
    p.drug LIKE '%spironolactone%' OR p.drug LIKE '%eplerenone%'
),
duration_calculation AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    -- Calculate duration in days
    (stoptime - starttime) / 86400 AS duration_days
  FROM
    relevant_prescriptions
  WHERE
    stoptime IS NOT NULL
)
SELECT
  AVG(duration_days) AS average_duration_days
FROM
  duration_calculation;