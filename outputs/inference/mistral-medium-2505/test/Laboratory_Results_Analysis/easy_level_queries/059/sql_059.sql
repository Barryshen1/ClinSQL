WITH
-- Get sepsis ICD codes (ICD-9 and ICD-10)
sepsis_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    icd_code IN ('995.91', '995.92', '785.52', 'R65.20', 'R65.21', 'R65.10', 'R65.11')
    OR long_title LIKE '%sepsis%'
),

-- Get male patients with sepsis admissions
male_sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN sepsis_icd_codes s ON d.icd_code = s.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 93  -- Approximate age (since anchor_age is age at first admission)
),

-- Get platelet counts on discharge day
platelet_counts_on_discharge AS (
  SELECT
    msa.subject_id,
    msa.hadm_id,
    msa.dischtime,
    le.valuenum AS platelet_count,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY msa.subject_id, msa.hadm_id ORDER BY ABS(TIMESTAMP_DIFF(le.charttime, msa.dischtime, SECOND))) AS time_diff_rank
  FROM male_sepsis_admissions msa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le ON msa.subject_id = le.subject_id AND msa.hadm_id = le.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli ON le.itemid = dli.itemid
  WHERE
    dli.label = 'Platelet Count'
    AND DATE(le.charttime) = DATE(msa.dischtime)  -- Same day as discharge
    AND le.valuenum IS NOT NULL
),

-- Get the closest platelet count to discharge time
closest_platelet_counts AS (
  SELECT
    subject_id,
    hadm_id,
    platelet_count
  FROM platelet_counts_on_discharge
  WHERE time_diff_rank = 1  -- Closest to discharge time
)

-- Calculate the 75th percentile platelet count
SELECT
  PERCENTILE_CONT(platelet_count, 0.75) OVER() AS percentile_75_platelet_count
FROM closest_platelet_counts
LIMIT 1;