WITH tia_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di ON a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` did ON di.icd_code = did.icd_code AND di.icd_version = did.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 72 AND 82
    AND (LOWER(did.long_title) LIKE '%transient ischemic attack%'
         OR LOWER(did.long_title) LIKE '%tia%')
),

icu_status AS (
  SELECT
    ta.hadm_id,
    ta.los_days,
    CASE WHEN i.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END AS icu_use
  FROM tia_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ta.hadm_id = i.hadm_id
  WHERE ta.los_days BETWEEN 1 AND 7
),

icd_imaging AS (
  SELECT
    pi.hadm_id,
    COUNT(*) AS icd_imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ct%'
     OR LOWER(dip.long_title) LIKE '%mri%'
     OR LOWER(dip.long_title) LIKE '%angiography%'
     OR LOWER(dip.long_title) LIKE '%ultrasound%'
     OR LOWER(dip.long_title) LIKE '%x-ray%'
     OR LOWER(dip.long_title) LIKE '%radiograph%'
     OR LOWER(dip.long_title) LIKE '%fluoroscopy%'
     OR LOWER(dip.long_title) LIKE '%nuclear medicine%'
     OR LOWER(dip.long_title) LIKE '%pet%'
     OR LOWER(dip.long_title) LIKE '%ct head%'
     OR LOWER(dip.long_title) LIKE '%ct brain%'
     OR LOWER(dip.long_title) LIKE '%mri brain%'
     OR LOWER(dip.long_title) LIKE '%mri head%'
  GROUP BY pi.hadm_id
),

icu_imaging AS (
  SELECT
    pe.hadm_id,
    COUNT(*) AS icu_imaging_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%ct%'
     OR LOWER(di.label) LIKE '%mri%'
     OR LOWER(di.label) LIKE '%angiography%'
     OR LOWER(di.label) LIKE '%ultrasound%'
     OR LOWER(di.label) LIKE '%x-ray%'
     OR LOWER(di.label) LIKE '%radiograph%'
     OR LOWER(di.label) LIKE '%fluoroscopy%'
     OR LOWER(di.label) LIKE '%nuclear medicine%'
     OR LOWER(di.label) LIKE '%pet%'
     OR LOWER(di.label) LIKE '%ct head%'
     OR LOWER(di.label) LIKE '%ct brain%'
     OR LOWER(di.label) LIKE '%mri brain%'
     OR LOWER(di.label) LIKE '%mri head%'
  GROUP BY pe.hadm_id
),

imaging_counts AS (
  SELECT
    COALESCE(i.hadm_id, u.hadm_id) AS hadm_id,
    COALESCE(i.icd_imaging_count, 0) + COALESCE(u.icu_imaging_count, 0) AS total_imaging_procedures
  FROM icd_imaging i
  FULL OUTER JOIN icu_imaging u ON i.hadm_id = u.hadm_id
)

SELECT
  CASE
    WHEN icu.los_days BETWEEN 1 AND 3 THEN '1–3 days'
    WHEN icu.los_days BETWEEN 4 AND 7 THEN '4–7 days'
  END AS los_group,
  icu.icu_use,
  COUNT(*) AS admission_count,
  AVG(COALESCE(ic.total_imaging_procedures, 0)) AS mean_imaging_procedures_per_admission
FROM icu_status icu
LEFT JOIN imaging_counts ic ON icu.hadm_id = ic.hadm_id
GROUP BY los_group, icu.icu_use
ORDER BY los_group, icu.icu_use;