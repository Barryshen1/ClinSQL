WITH patient_ages AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in days as a decimal
    DATETIME_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60.0) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp`.patients p
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.admissions a
  ON
    p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND a.dischtime IS NOT NULL
),
admission_diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    did.long_title
  FROM
    `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN
    `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses did
  ON
    di.icd_code = did.icd_code
    AND di.icd_version = did.icd_version
),
heart_failure_codes AS (
  SELECT DISTINCT hadm_id
  FROM admission_diagnoses
  WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
     OR (icd_version = 9 AND icd_code LIKE '428%')
),
copd_codes AS (
  SELECT DISTINCT hadm_id
  FROM admission_diagnoses
  WHERE (icd_version = 10 AND icd_code LIKE 'J44%')
     OR (icd_version = 9 AND (icd_code LIKE '496%' OR icd_code LIKE '491%' OR icd_code LIKE '492%'))
),
qualified_admissions AS (
  SELECT
    pa.hadm_id,
    pa.los_days
  FROM
    patient_ages pa
  INNER JOIN
    heart_failure_codes hf
  ON
    pa.hadm_id = hf.hadm_id
  INNER JOIN
    copd_codes c
  ON
    pa.hadm_id = c.hadm_id
  WHERE
    pa.age_at_admission >= 77
    AND pa.age_at_admission <= 87
)
SELECT
  STDDEV(los_days) AS sd_los_days
FROM
  qualified_admissions;