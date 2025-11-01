WITH
-- Define UGIB and COPD exacerbation ICD codes
ugib_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '578.%' OR icd_code = 'K92.2'
),
copd_exacerbation_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN ('491.21', '491.22', '493.21', '493.22', 'J44.1')
),

-- Get patients with both UGIB and COPD exacerbation
patients_with_conditions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.icd_code IN (SELECT icd_code FROM ugib_codes)
      INTERSECT DISTINCT
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.icd_code IN (SELECT icd_code FROM copd_exacerbation_codes)
    )
)

-- Calculate median LOS
SELECT
  PERCENTILE_CONT(los_days, 0.5) OVER() AS median_los_days
FROM patients_with_conditions
LIMIT 1;