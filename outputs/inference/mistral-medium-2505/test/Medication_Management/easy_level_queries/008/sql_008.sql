WITH
-- Get male patients aged 64-74
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 64 AND 74
),

-- Get admissions for eligible patients
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
),

-- Get aspirin prescriptions
aspirin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(
      IFNULL(p.stoptime, a.dischtime),
      p.starttime,
      DAY
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    patient_admissions a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%aspirin%'
),

-- Get P2Y12 inhibitor prescriptions (clopidogrel, ticagrelor, prasugrel)
p2y12_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    TIMESTAMP_DIFF(
      IFNULL(p.stoptime, a.dischtime),
      p.starttime,
      DAY
    ) AS duration_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    patient_admissions a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE
    LOWER(p.drug) LIKE '%clopidogrel%'
    OR LOWER(p.drug) LIKE '%ticagrelor%'
    OR LOWER(p.drug) LIKE '%prasugrel%'
),

-- Combine aspirin and P2Y12 prescriptions per admission
combined_prescriptions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.duration_days AS aspirin_duration,
    p.duration_days AS p2y12_duration
  FROM
    aspirin_prescriptions a
  JOIN
    p2y12_prescriptions p ON a.subject_id = p.subject_id AND a.hadm_id = p.hadm_id
)

-- Calculate median duration of antiplatelet therapy per admission
SELECT
  PERCENTILE_CONT(combined_prescriptions.aspirin_duration, 0.5) OVER() AS median_aspirin_duration,
  PERCENTILE_CONT(combined_prescriptions.p2y12_duration, 0.5) OVER() AS median_p2y12_duration
FROM
  combined_prescriptions
LIMIT 1;