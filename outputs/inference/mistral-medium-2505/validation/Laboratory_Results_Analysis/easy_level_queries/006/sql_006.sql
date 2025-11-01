WITH
-- Identify 50-year-old female patients with COPD
copd_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 50
    AND di.long_title LIKE '%COPD%'  -- COPD diagnosis
),

-- Get all hospital admissions for these patients
copd_admissions AS (
  SELECT a.hadm_id, a.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN copd_patients cp ON a.subject_id = cp.subject_id
),

-- Get serum sodium measurements during these admissions
sodium_measurements AS (
  SELECT
    le.hadm_id,
    le.valuenum AS sodium_value
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  JOIN copd_admissions ca ON le.hadm_id = ca.hadm_id
  WHERE dli.label = 'Sodium, Serum'  -- Sodium measurement
    AND le.valuenum IS NOT NULL
),

-- Find the nadir (minimum) sodium value for each admission
nadir_sodium AS (
  SELECT
    hadm_id,
    MIN(sodium_value) AS nadir_sodium_value
  FROM sodium_measurements
  GROUP BY hadm_id
)

-- Calculate the standard deviation of nadir sodium values
SELECT
  STDDEV(nadir_sodium_value) AS stddev_nadir_sodium
FROM nadir_sodium;