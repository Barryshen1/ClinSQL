WITH
-- Define age range and gender filter
patient_filter AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 77 AND 87
),

-- Identify asthma exacerbation admissions
asthma_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS admission_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_filter p ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE
    -- ICD-10 codes for asthma (J45.* and J44.*)
    (d.icd_code LIKE 'J45%' OR d.icd_code LIKE 'J44%')
    AND d.icd_version = 10
),

-- Identify ICU stays
icu_stays AS (
  SELECT DISTINCT
    subject_id,
    hadm_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays`
),

-- Count CT/MRI procedures per admission
ct_mri_counts AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT p.icd_code) AS ct_mri_count
  FROM
    asthma_admissions a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.procedures_icd` p ON a.hadm_id = p.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` d ON p.icd_code = d.icd_code AND p.icd_version = d.icd_version
  WHERE
    -- ICD-9/10 codes for CT/MRI procedures
    (d.long_title LIKE '%CT%' OR d.long_title LIKE '%MRI%' OR d.long_title LIKE '%computed tomography%' OR d.long_title LIKE '%magnetic resonance%')
  GROUP BY
    a.hadm_id
),

-- Combine all data with admission duration categories and ICU status
final_data AS (
  SELECT
    a.hadm_id,
    CASE
      WHEN a.admission_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN a.admission_days BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE NULL
    END AS admission_duration,
    CASE
      WHEN EXISTS (
        SELECT 1 FROM icu_stays i
        WHERE i.hadm_id = a.hadm_id
      ) THEN 'ICU'
      ELSE 'Non-ICU'
    END AS icu_status,
    COALESCE(c.ct_mri_count, 0) AS ct_mri_count
  FROM
    asthma_admissions a
  LEFT JOIN
    ct_mri_counts c ON a.hadm_id = c.hadm_id
  WHERE
    a.admission_days BETWEEN 1 AND 8
)

-- Final aggregation
SELECT
  admission_duration,
  icu_status,
  COUNT(hadm_id) AS admission_count,
  AVG(ct_mri_count) AS mean_ct_mri,
  MIN(ct_mri_count) AS min_ct_mri,
  MAX(ct_mri_count) AS max_ct_mri
FROM
  final_data
GROUP BY
  admission_duration,
  icu_status
ORDER BY
  admission_duration,
  icu_status;