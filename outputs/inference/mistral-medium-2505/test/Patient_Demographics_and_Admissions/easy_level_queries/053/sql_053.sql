WITH
-- Get female patients aged 52-62
female_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age BETWEEN 52 AND 62
),

-- Get admissions with AKI diagnosis
aki_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN female_patients p ON a.subject_id = p.subject_id
  WHERE d.icd_code IN (
    -- ICD-9 codes for AKI
    '5845', '5846', '5847', '5848', '5849',
    -- ICD-10 codes for AKI
    'N170', 'N171', 'N172', 'N178', 'N179'
  )
  AND a.hospital_expire_flag = 0  -- Exclude patients who died during admission
),

-- Find 30-day readmissions
readmissions AS (
  SELECT
    a1.hadm_id AS initial_hadm_id,
    a1.subject_id,
    a1.dischtime,
    a2.hadm_id AS readmit_hadm_id,
    a2.admittime AS readmit_time,
    TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) AS days_to_readmit,
    CASE WHEN TIMESTAMP_DIFF(a2.admittime, a1.dischtime, DAY) <= 30 THEN 1 ELSE 0 END AS is_30day_readmit
  FROM aki_admissions a1
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a2 ON a1.subject_id = a2.subject_id
  WHERE a2.admittime > a1.dischtime
    AND a2.hadm_id != a1.hadm_id
),

-- Aggregate readmission status per initial admission
readmission_status AS (
  SELECT
    initial_hadm_id,
    subject_id,
    MAX(is_30day_readmit) AS had_30day_readmit
  FROM readmissions
  GROUP BY initial_hadm_id, subject_id
),

-- Calculate standard deviation of readmission status
readmission_stats AS (
  SELECT
    STDDEV(had_30day_readmit) AS stddev_30day_readmit
  FROM readmission_status
)

SELECT
  stddev_30day_readmit
FROM readmission_stats;