WITH
-- Get female patients aged 77-87
female_patients_77_87 AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 77 AND 87
),

-- Get their hospital admissions
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    female_patients_77_87 p ON a.subject_id = p.subject_id
),

-- Identify ARB prescriptions (using common ARB drug names)
arb_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.pharmacy_id,
    p.starttime,
    p.stoptime,
    p.drug,
    -- Calculate duration in days
    TIMESTAMP_DIFF(p.stoptime, p.starttime, DAY) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    patient_admissions pa ON p.subject_id = pa.subject_id AND p.hadm_id = pa.hadm_id
  WHERE
    -- Filter for common ARB drugs
    (LOWER(p.drug) LIKE '%losartan%'
     OR LOWER(p.drug) LIKE '%valsartan%'
     OR LOWER(p.drug) LIKE '%irbesartan%'
     OR LOWER(p.drug) LIKE '%candesartan%'
     OR LOWER(p.drug) LIKE '%olmesartan%'
     OR LOWER(p.drug) LIKE '%telmisartan%'
     OR LOWER(p.drug) LIKE '%azilsartan%')
    -- Ensure valid time range
    AND p.stoptime > p.starttime
    AND p.stoptime IS NOT NULL
    AND p.starttime IS NOT NULL
)

-- Calculate average duration
SELECT
  AVG(duration_days) AS avg_arb_prescription_duration_days,
  COUNT(*) AS number_of_prescriptions
FROM
  arb_prescriptions
WHERE
  duration_days > 0  -- Exclude zero or negative durations;