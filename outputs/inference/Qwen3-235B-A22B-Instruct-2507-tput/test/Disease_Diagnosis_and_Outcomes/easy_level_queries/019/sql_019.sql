WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    -- Compute age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime,
    di.icd_code,
    di.icd_version,
    di.seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  WHERE di.seq_num = 1  -- Primary diagnosis
    AND p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 67 AND 77
),
sepsis_admissions AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    -- Compute length of stay in days
    DATETIME_DIFF(dischtime, admittime, DAY) AS los_days
  FROM patient_admissions
  WHERE (icd_version = 9 AND icd_code IN ('995.92', '785.52'))
     OR (icd_version = 10 AND icd_code IN ('A41.9', 'R65.20', 'R65.21'))
    AND admittime IS NOT NULL
    AND dischtime IS NOT NULL
)
SELECT
  STDDEV(los_days) AS sd_los_days
FROM sepsis_admissions;