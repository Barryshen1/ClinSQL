WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 84 AND 94
    AND a.dischtime IS NOT NULL  -- Ensure discharge time is available
),
stroke_admissions AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.age_at_admission,
    d.icd_code
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON pa.subject_id = d.subject_id
    AND pa.hadm_id = d.hadm_id
  WHERE d.seq_num = 1  -- primary diagnosis
    AND d.icd_version = 10
    AND d.icd_code LIKE 'I63%'  -- ICD-10 codes for ischemic stroke
)
SELECT 
  MAX(DATE_DIFF(dischtime, admittime, DAY)) AS max_los_days
FROM stroke_admissions;