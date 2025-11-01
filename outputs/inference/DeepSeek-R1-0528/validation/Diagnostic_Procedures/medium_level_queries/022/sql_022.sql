WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id,
    adm.admission_type,
    DATE_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) = 74
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE 
        diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%') 
          OR 
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),

filtered_cohort AS (
  SELECT 
    hadm_id,
    CASE 
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7'
    END AS los_group,
    CASE 
      WHEN admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
      WHEN admission_type = 'ELECTIVE' THEN 'Elective'
    END AS admission_group
  FROM cohort
  WHERE 
    los_days BETWEEN 1 AND 7
    AND admission_type IN ('EMERGENCY', 'URGENT', 'ELECTIVE')
),

non_invasive_codes AS (
  SELECT DISTINCT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE 
    LOWER(long_description) LIKE '%x-ray%' OR
    LOWER(long_description) LIKE '%xray%' OR
    LOWER(long_description) LIKE '%radiograph%' OR
    LOWER(long_description) LIKE '%ct scan%' OR
    LOWER(long_description) LIKE '%computed tomography%' OR
    LOWER(long_description) LIKE '%mri%' OR
    LOWER(long_description) LIKE '%magnetic resonance imaging%' OR
    LOWER(long_description) LIKE '%ultrasound%' OR
    LOWER(long_description) LIKE '%echocardiogram%' OR
    LOWER(long_description) LIKE '%electrocardiogram%' OR
    LOWER(long_description) LIKE '%ecg%' OR
    LOWER(long_description) LIKE '%ekg%' OR
    LOWER(long_description) LIKE '%electroencephalogram%' OR
    LOWER(long_description) LIKE '%eeg%' OR
    LOWER(long_description) LIKE '%pulmonary function test%' OR
    LOWER(long_description) LIKE '%pft%' OR
    LOWER(long_description) LIKE '%spirometry%'
),

test_counts AS (
  SELECT 
    hadm_id,
    COUNT(*) AS num_tests
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` hcp
  WHERE hcp.hcpcs_cd IN (SELECT code FROM non_invasive_codes)
  GROUP BY hadm_id
)

SELECT 
  fc.los_group,
  fc.admission_group,
  COUNT(fc.hadm_id) AS num_admissions,
  AVG(COALESCE(tc.num_tests, 0)) AS mean_tests_per_admission
FROM filtered_cohort fc
LEFT JOIN test_counts tc
  ON fc.hadm_id = tc.hadm_id
GROUP BY fc.los_group, fc.admission_group
ORDER BY fc.los_group, fc.admission_group;