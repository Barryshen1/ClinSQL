WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 78 AND 88
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
dvt_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON pa.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%deep vein thrombosis%'
     OR LOWER(d.long_title) LIKE '%dvt%'
),
noninvasive_procs AS (
  SELECT
    da.hadm_id,
    da.los_days,
    da.had_icu,
    dip.long_title AS proc_title
  FROM dvt_admissions da
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.procedures_icd pi
    ON da.hadm_id = pi.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_procedures dip
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ultrasound%'
     OR LOWER(dip.long_title) LIKE '%doppler%'
     OR LOWER(dip.long_title) LIKE '%echo%'
     OR LOWER(dip.long_title) LIKE '%ct%'
     OR LOWER(dip.long_title) LIKE '%mri%'
     OR LOWER(dip.long_title) LIKE '%x-ray%'
     OR LOWER(dip.long_title) LIKE '%radiography%'
    -- Exclude clearly invasive
    AND LOWER(dip.long_title) NOT LIKE '%biopsy%'
    AND LOWER(dip.long_title) NOT LIKE '%catheterization%'
    AND LOWER(dip.long_title) NOT LIKE '%angiography%'
    AND LOWER(dip.long_title) NOT LIKE '%insertion%'
    AND LOWER(dip.long_title) NOT LIKE '%drain%'
    AND LOWER(dip.long_title) NOT LIKE '%excision%'
),
los_groups AS (
  SELECT
    hadm_id,
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN los_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS los_group,
    had_icu,
    proc_title
  FROM noninvasive_procs
  WHERE los_days BETWEEN 1 AND 8
),
summary AS (
  SELECT
    los_group,
    CASE WHEN had_icu = 1 THEN 'ICU' ELSE 'No ICU' END AS icu_status,
    COUNT(*) AS total_diagnostics,
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM los_groups
  GROUP BY los_group, icu_status
)
SELECT
  los_group,
  icu_status,
  total_admissions,
  total_diagnostics,
  ROUND(total_diagnostics / total_admissions, 2) AS mean_diagnostics_per_admission
FROM summary
ORDER BY los_group, icu_status;