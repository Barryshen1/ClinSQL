WITH
-- Get female patients aged 86-96
female_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 86 AND 96
),

-- Get their hospital admissions
female_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients p ON a.subject_id = p.subject_id
),

-- Get atorvastatin prescriptions with dose information
atorvastatin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.dose_val_rx,
    p.dose_unit_rx,
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    female_admissions a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%atorvastatin%'
    AND SAFE_CAST(p.dose_val_rx AS FLOAT64) BETWEEN 40 AND 80
    AND p.dose_unit_rx = 'mg'
    AND p.stoptime IS NOT NULL
    AND p.starttime < p.stoptime
)

-- Find the minimum duration
SELECT
  MIN(duration_days) AS min_duration_days
FROM
  atorvastatin_prescriptions
WHERE
  duration_days > 0;