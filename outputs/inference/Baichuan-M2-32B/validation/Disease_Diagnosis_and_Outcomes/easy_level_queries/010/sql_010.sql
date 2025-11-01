WITH patient_birth AS (
  SELECT
    subject_id,
    DATE_SUB(CAST(CONCAT(anchor_year, '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE anchor_year IS NOT NULL
    AND anchor_age IS NOT NULL
),
admissions_with_age AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN patient_birth p ON a.subject_id = p.subject_id
  WHERE a.gender = 'F'
    AND a.dischtime IS NOT NULL
),
copd_admissions AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.admittime,
    aa.dischtime,
    aa.age_at_admission
  FROM admissions_with_age aa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON aa.subject_id = d.subject_id
    AND aa.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND d.icd_code = 'J44.1'
    AND d.icd_version = 10
),
los_data AS (
  SELECT
    hadm_id,
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0 AS los_days
  FROM copd_admissions
  WHERE age_at_admission BETWEEN 49 AND 59
)
SELECT 
  APPROX_QUANTILES(los_days, 100)[SAFE_OFFSET(25)] AS p25_los
FROM los_data;