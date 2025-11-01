WITH
-- Filter for female patients aged 83-93
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 83 AND 93
),

-- Get admissions for these patients with valid discharge times
valid_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    a.dischtime IS NOT NULL
),

-- Identify primary diagnosis of community-acquired pneumonia (CAP)
cap_diagnoses AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    d.icd_code,
    d.seq_num,
    ROW_NUMBER() OVER (PARTITION BY d.hadm_id ORDER BY d.seq_num) AS diagnosis_rank
  FROM
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN
    valid_admissions a ON d.hadm_id = a.hadm_id
  WHERE
    -- ICD-10 codes for pneumonia (J12-J18)
    d.icd_code LIKE 'J12%' OR d.icd_code LIKE 'J13%' OR d.icd_code LIKE 'J14%'
    OR d.icd_code LIKE 'J15%' OR d.icd_code LIKE 'J16%' OR d.icd_code LIKE 'J17%'
    OR d.icd_code LIKE 'J18%'
),

-- Filter for admissions where CAP is the primary diagnosis
cap_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.los_days
  FROM
    valid_admissions a
  JOIN
    cap_diagnoses d ON a.hadm_id = d.hadm_id
  WHERE
    d.diagnosis_rank = 1  -- Primary diagnosis
)

-- Calculate median LOS
SELECT
  PERCENTILE_CONT(a.los_days, 0.5) OVER() AS median_los_days
FROM
  cap_admissions a
LIMIT 1;