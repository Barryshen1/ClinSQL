WITH
-- Define ACS ICD codes (both ICD-9 and ICD-10)
acs_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    -- ICD-9 codes for ACS
    '41000', '41001', '41002', '41010', '41011', '41012',
    '41020', '41021', '41022', '41030', '41031', '41032',
    '41040', '41041', '41042', '41050', '41051', '41052',
    '41060', '41061', '41062', '41070', '41071', '41072',
    '41080', '41081', '41082', '41090', '41091', '41092',
    '4111',
    -- ICD-10 codes for ACS
    'I200', 'I2101', 'I2102', 'I2109', 'I2111', 'I2119',
    'I2121', 'I2129', 'I213', 'I214', 'I219', 'I21A1', 'I21A9'
  )
),

-- Get ACS admissions with age 77-87 and female gender
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    d.seq_num AS diagnosis_seq_num,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    EXTRACT(YEAR FROM a.admittime) AS admission_year,
    CASE
      WHEN d.seq_num = 1 THEN 'Primary'
      ELSE 'Secondary'
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN acs_icd_codes acs ON d.icd_code = acs.icd_code AND d.icd_version = acs.icd_version
  WHERE
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 77 AND 87
),

-- Count radiography/CT procedures per admission
radiology_counts AS (
  SELECT
    h.subject_id,
    h.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS radiology_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  WHERE h.hcpcs_cd IN (
    -- Common radiography/CT HCPCS codes
    '71010', '71250', '71260', '71270',
    '71020', '71030', '71034', '71035', '71045', '71046',
    '71047', '71048', '71100', '71101', '71110', '71111',
    '71120', '71130', '71200', '71210', '71220', '71230',
    '71240', '71250', '71260', '71270', '71275', '71276',
    '71277', '71278', '71279', '71280', '71281', '71282',
    '71283', '71284', '71285', '71286', '71287', '71288',
    '71289', '71290', '71291', '71292', '71293', '71294',
    '71295', '71296', '71297', '71298', '71299'
  )
  GROUP BY h.subject_id, h.hadm_id
)

-- Final aggregation
SELECT
  CASE
    WHEN a.los_days BETWEEN 1 AND 4 THEN '1-4 days'
    WHEN a.los_days BETWEEN 5 AND 8 THEN '5-8 days'
    ELSE 'Other'
  END AS stay_duration,
  a.diagnosis_type,
  COUNT(DISTINCT a.hadm_id) AS admission_count,
  AVG(COALESCE(r.radiology_count, 0)) AS mean_radiology_count,
  MIN(COALESCE(r.radiology_count, 0)) AS min_radiology_count,
  MAX(COALESCE(r.radiology_count, 0)) AS max_radiology_count
FROM acs_admissions a
LEFT JOIN radiology_counts r ON a.hadm_id = r.hadm_id
WHERE a.los_days BETWEEN 1 AND 8
GROUP BY stay_duration, diagnosis_type
ORDER BY stay_duration, diagnosis_type;