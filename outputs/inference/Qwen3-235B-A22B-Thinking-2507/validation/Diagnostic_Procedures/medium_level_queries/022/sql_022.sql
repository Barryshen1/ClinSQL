WITH eligible_admissions AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.admission_type,
    -- Compute LOS in days (fractional)
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    -- Compute age at admission
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) = 74
    -- Filter for heart failure: join with diagnoses_icd
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 2 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 3 AND d.icd_code LIKE 'I50%')
        )
    )
),

diagnostics_count AS (
  SELECT 
    p.hadm_id,
    COUNT(*) AS num_diagnostics
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` p
  INNER JOIN eligible_admissions ea ON p.hadm_id = ea.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d
    ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE 
    LOWER(d.long_title) LIKE '%x-ray%' OR
    LOWER(d.long_title) LIKE '%radiograph%' OR
    LOWER(d.long_title) LIKE '%ct%' OR
    LOWER(d.long_title) LIKE '%computed tomography%' OR
    LOWER(d.long_title) LIKE '%mri%' OR
    LOWER(d.long_title) LIKE '%magnetic resonance%' OR
    LOWER(d.long_title) LIKE '%ultrasound%' OR
    LOWER(d.long_title) LIKE '%echo%' OR
    LOWER(d.long_title) LIKE '%electrocardiogram%' OR
    LOWER(d.long_title) LIKE '%ecg%' OR
    LOWER(d.long_title) LIKE '%electroencephalogram%' OR
    LOWER(d.long_title) LIKE '%eeg%' OR
    LOWER(d.long_title) LIKE '%pulmonary function test%' OR
    LOWER(d.long_title) LIKE '%pft%'
  GROUP BY p.hadm_id
),

admission_groups AS (
  SELECT
    ea.hadm_id,
    ea.los_days,
    CASE 
      WHEN ea.los_days >= 1 AND ea.los_days < 5 THEN '1-4 days'
      WHEN ea.los_days >= 5 AND ea.los_days <= 7 THEN '5-7 days'
      ELSE NULL
    END AS stay_duration_group,
    CASE 
      WHEN ea.admission_type IN ('EMERGENCY', 'URGENT') THEN 'ED/Urgent'
      WHEN ea.admission_type = 'ELECTIVE' THEN 'Elective'
      ELSE NULL
    END AS admission_category
  FROM eligible_admissions ea
  WHERE ea.los_days >= 1  -- Exclude stays less than 1 day
)

SELECT
  ag.stay_duration_group,
  ag.admission_category,
  AVG(COALESCE(dc.num_diagnostics, 0)) AS mean_diagnostics_per_admission,
  COUNT(ag.hadm_id) AS admission_count
FROM admission_groups ag
LEFT JOIN diagnostics_count dc ON ag.hadm_id = dc.hadm_id
WHERE ag.stay_duration_group IS NOT NULL
  AND ag.admission_category IS NOT NULL
GROUP BY ag.stay_duration_group, ag.admission_category
ORDER BY ag.stay_duration_group, ag.admission_category;