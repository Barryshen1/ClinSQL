WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime,
    -- Hospital LOS in days (as a decimal)
    DATETIME_DIFF(a.dischtime, a.admittime, MINUTE) / 1440.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
),
primary_diagnoses AS (
  SELECT
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    d.long_title
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE di.seq_num = 1  -- Primary diagnosis
),
acs_diagnoses AS (
  SELECT hadm_id
  FROM primary_diagnoses
  WHERE LOWER(long_title) LIKE '%myocardial infarction%'
     OR LOWER(long_title) LIKE '%acute coronary%'
     OR LOWER(long_title) LIKE '%ischemic heart%'
     OR LOWER(long_title) LIKE '%angina pectoris, unstable%'
)
SELECT
  AVG(pa.los_days) AS average_hospital_los_days
FROM patient_admissions pa
JOIN acs_diagnoses a
  ON pa.hadm_id = a.hadm_id
WHERE pa.age_at_admission BETWEEN 78 AND 88;