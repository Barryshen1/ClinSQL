WITH
-- Define UGIB and COPD exacerbation ICD-10 codes
ugib_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
  AND (
    icd_code IN ('K922', 'K250', 'K252', 'K254', 'K256', 'K260', 'K262', 'K264', 'K266', 'K270', 'K272', 'K274', 'K276', 'K280', 'K282', 'K284', 'K286')
    OR icd_code LIKE 'K25%' OR icd_code LIKE 'K26%' OR icd_code LIKE 'K27%' OR icd_code LIKE 'K28%'
  )
),
copd_exacerbation_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_version = 10
  AND icd_code IN ('J440', 'J441')
),

-- Get patients with both UGIB and COPD exacerbation in the same admission
target_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS length_of_stay_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  JOIN ugib_codes u ON d1.icd_code = u.icd_code
  JOIN copd_exacerbation_codes c ON d2.icd_code = c.icd_code
  WHERE p.gender = 'M'
  AND p.anchor_age BETWEEN 86 AND 96
  AND d1.icd_version = 10
  AND d2.icd_version = 10
  AND d1.seq_num <> d2.seq_num  -- Ensure different diagnoses
)

-- Calculate average LOS
SELECT
  AVG(length_of_stay_days) AS avg_length_of_stay_days
FROM target_admissions;