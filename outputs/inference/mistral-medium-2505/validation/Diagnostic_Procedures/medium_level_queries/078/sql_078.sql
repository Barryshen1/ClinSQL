WITH
-- Define TIA ICD codes (ICD-9 and ICD-10)
tia_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '435.%'  -- ICD-9 TIA codes
     OR icd_code LIKE 'G45.%'  -- ICD-10 TIA codes
),

-- Get female patients aged 88-98 with TIA diagnosis
eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON p.subject_id = d.subject_id
  JOIN tia_codes t ON d.icd_code = t.icd_code
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 88 AND 98
),

-- Get admissions for these patients with length of stay 1-7 days
eligible_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN TRUE ELSE FALSE END AS had_icu_stay
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN eligible_patients e ON a.subject_id = e.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON a.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  WHERE TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),

-- Count CT/MRI studies per admission
imaging_counts AS (
  SELECT
    e.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_studies_count
  FROM eligible_admissions e
  JOIN `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h ON e.hadm_id = h.hadm_id
  WHERE h.hcpcs_cd LIKE '704%'  -- CT head codes
     OR h.hcpcs_cd LIKE '7055%'  -- MRI brain codes
  GROUP BY e.hadm_id
)

-- Final aggregation with median and IQR
SELECT
  CASE
    WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  CASE WHEN had_icu_stay THEN 'With ICU' ELSE 'Without ICU' END AS icu_status,
  COUNT(DISTINCT e.hadm_id) AS admission_count,
  APPROX_QUANTILES(i.imaging_studies_count, 100)[OFFSET(50)] AS median_imaging_studies,
  APPROX_QUANTILES(i.imaging_studies_count, 100)[OFFSET(25)] AS q1_imaging_studies,
  APPROX_QUANTILES(i.imaging_studies_count, 100)[OFFSET(75)] AS q3_imaging_studies
FROM eligible_admissions e
LEFT JOIN imaging_counts i ON e.hadm_id = i.hadm_id
GROUP BY los_group, icu_status
ORDER BY los_group, icu_status;