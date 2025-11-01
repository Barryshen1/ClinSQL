WITH 
-- Define lower GI bleed diagnosis codes (fixed ICD-10 logic for K57 codes)
lower_gi_bleed_codes AS (
  SELECT icd_version, icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code IN ('56203', '56213', '56984'))
    OR (icd_version = 10 AND (
      icd_code IN ('K5521', 'K625', 'K635')
      OR icd_code LIKE 'K572%'
      OR icd_code LIKE 'K573%'
    ))
),
-- Define non-invasive diagnostic procedure codes (fixed ILIKE and column name)
non_invasive_diagnostics AS (
  SELECT code AS hcpcs_cd
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    LOWER(short_description) LIKE '%x-ray%' OR
    LOWER(short_description) LIKE '%ct%' OR
    LOWER(short_description) LIKE '%mri%' OR
    LOWER(short_description) LIKE '%ultrasound%' OR
    LOWER(short_description) LIKE '%ecg%' OR
    LOWER(short_description) LIKE '%electrocardiogram%' OR
    LOWER(short_description) LIKE '%eeg%' OR
    LOWER(short_description) LIKE '%electroencephalogram%' OR
    LOWER(short_description) LIKE '%pulmonary function test%' OR
    LOWER(short_description) LIKE '%pft%'
),
-- Get admissions meeting criteria (female, age 62-72, lower GI bleed)
eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    -- Determine ICU status
    CASE WHEN i.stay_id IS NOT NULL THEN 'ICU' ELSE 'Non-ICU' END AS icu_status
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  -- Join to get diagnosis of lower GI bleed
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN lower_gi_bleed_codes lgb
    ON d.icd_version = lgb.icd_version AND d.icd_code = lgb.icd_code
  -- Left join to check for ICU stay
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    -- Calculate age at admission
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 62 AND 72
),
-- Count non-invasive diagnostics per admission
diagnostics_count AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS diagnostic_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN non_invasive_diagnostics d
    ON h.hcpcs_cd = d.hcpcs_cd
  GROUP BY h.hadm_id
)
-- Final query: calculate mean diagnostics by LOS group and ICU status
SELECT
  CASE 
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
    ELSE NULL
  END AS los_group,
  icu_status,
  AVG(COALESCE(dc.diagnostic_count, 0)) AS mean_diagnostics
FROM eligible_admissions ea
LEFT JOIN diagnostics_count dc
  ON ea.hadm_id = dc.hadm_id
WHERE los_days BETWEEN 1 AND 7  -- Only include admissions with LOS 1-7 days
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;