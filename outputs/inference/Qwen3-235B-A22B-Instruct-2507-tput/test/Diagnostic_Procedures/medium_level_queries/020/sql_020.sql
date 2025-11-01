WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 72 AND 82
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime <= a.dischtime
),

-- Filter admissions with TIA diagnosis
tia_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%transient ischemic attack%'
     OR LOWER(d.long_title) LIKE '%tia%'
     OR (di.icd_code = 'G459' AND di.icd_version = 10) -- ICD-10 code for TIA
     OR (di.icd_code = '4359' AND di.icd_version = 9) -- ICD-9 code for TIA
),

-- Define imaging procedures using keywords in long_title
imaging_procs AS (
  SELECT
    hadm_id,
    COUNT(*) AS proc_count
  FROM `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures d
    ON pi.icd_code = d.icd_code AND pi.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%ct%'
     OR LOWER(d.long_title) LIKE '%mri%'
     OR LOWER(d.long_title) LIKE '%magnetic resonance%'
     OR LOWER(d.long_title) LIKE '%angiogram%'
     OR LOWER(d.long_title) LIKE '%echocardiogram%'
     OR LOWER(d.long_title) LIKE '%ultrasound%'
     OR LOWER(d.long_title) LIKE '%x-ray%'
     OR LOWER(d.long_title) LIKE '%fluoroscopy%'
     OR LOWER(d.long_title) LIKE '%nuclear medicine%'
     OR LOWER(d.long_title) LIKE '%pet scan%'
  GROUP BY hadm_id
),

-- ICU use flag
icu_use AS (
  SELECT DISTINCT
    hadm_id,
    'Yes' AS icu_flag
  FROM `physionet-data.mimiciv_3_1_icu`.icustays
)

SELECT
  CASE
    WHEN ta.los_days BETWEEN 1 AND 3 THEN '1-3 days'
    WHEN ta.los_days BETWEEN 4 AND 7 THEN '4-7 days'
  END AS los_group,
  COALESCE(iu.icu_flag, 'No') AS icu_use,
  COUNT(*) AS admission_count,
  AVG(COALESCE(ip.proc_count, 0)) AS mean_imaging_procs_per_admission
FROM tia_admissions ta
LEFT JOIN imaging_procs ip
  ON ta.hadm_id = ip.hadm_id
LEFT JOIN icu_use iu
  ON ta.hadm_id = iu.hadm_id
WHERE ta.los_days BETWEEN 1 AND 7
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;