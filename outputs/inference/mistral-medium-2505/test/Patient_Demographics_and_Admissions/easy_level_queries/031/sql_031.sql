WITH
-- Identify female patients aged 38-48
eligible_patients AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year,
    dod
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
),

-- Get all HF admissions (ICD-10 codes for heart failure: I50.*, I11.0, I13.0, I13.2)
hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) AS admission_seq
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    a.subject_id IN (SELECT subject_id FROM eligible_patients)
    AND (
      (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
      OR (d.icd_version = 10 AND d.icd_code IN ('I11.0', 'I13.0', 'I13.2'))
    )
),

-- Get first HF admission for each patient
first_hf_admissions AS (
  SELECT
    subject_id,
    hadm_id,
    admittime,
    dischtime,
    deathtime,
    hospital_expire_flag
  FROM
    hf_admissions
  WHERE
    admission_seq = 1
),

-- Find any readmissions within 30 days of discharge from first HF admission
readmissions AS (
  SELECT
    f.subject_id,
    f.hadm_id AS first_hadm_id,
    f.dischtime,
    a.hadm_id AS readmit_hadm_id,
    a.admittime AS readmit_admittime,
    TIMESTAMP_DIFF(a.admittime, f.dischtime, DAY) AS days_to_readmit
  FROM
    first_hf_admissions f
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.subject_id = a.subject_id
    AND a.admittime > f.dischtime
    AND TIMESTAMP_DIFF(a.admittime, f.dischtime, DAY) <= 30
  WHERE
    f.hospital_expire_flag = 0  -- Exclude patients who died during first admission
)

-- Calculate readmission rate
SELECT
  COUNT(DISTINCT r.subject_id) AS num_patients_with_readmission,
  COUNT(DISTINCT f.subject_id) AS total_patients,
  COUNT(DISTINCT r.subject_id) / COUNT(DISTINCT f.subject_id) AS readmission_rate
FROM
  first_hf_admissions f
LEFT JOIN
  readmissions r
  ON f.subject_id = r.subject_id
WHERE
  f.hospital_expire_flag = 0;