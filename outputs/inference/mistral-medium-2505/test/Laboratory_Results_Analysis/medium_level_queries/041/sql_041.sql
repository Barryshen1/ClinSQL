WITH
-- Define ACS ICD codes (example codes, adjust as needed)
acs_icd_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9',  -- STEMI
    'I20.0', 'I20.1', 'I20.8', 'I20.9'                     -- Unstable angina
  )
),

-- Get male patients aged 43-53 with ACS
acs_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN acs_icd_codes acs ON d.icd_code = acs.icd_code AND d.icd_version = acs.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 43 AND 53
),

-- Get hs-Troponin T lab events (assuming itemid for hs-TnT is known or can be identified)
hs_tnt_labs AS (
  SELECT
    l.subject_id,
    l.hadm_id,
    l.charttime,
    l.valuenum,
    l.valueuom,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime) AS lab_rank
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d ON l.itemid = d.itemid
  WHERE d.label LIKE '%Troponin T%'  -- Adjust to match hs-TnT specifically
    AND l.valuenum > 0.014           -- 99th percentile ULN for hs-TnT (ng/mL)
),

-- Get first hs-TnT value per admission
first_hs_tnt AS (
  SELECT
    subject_id,
    hadm_id,
    valuenum
  FROM hs_tnt_labs
  WHERE lab_rank = 1
)

-- Calculate median and IQR
SELECT
  PERCENTILE_CONT(valuenum, 0.5) OVER() AS median_hs_tnt,
  PERCENTILE_CONT(valuenum, 0.25) OVER() AS q1_hs_tnt,
  PERCENTILE_CONT(valuenum, 0.75) OVER() AS q3_hs_tnt,
  PERCENTILE_CONT(valuenum, 0.75) OVER() - PERCENTILE_CONT(valuenum, 0.25) OVER() AS iqr_hs_tnt
FROM first_hs_tnt
LIMIT 1;