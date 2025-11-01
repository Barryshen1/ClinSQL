WITH
-- 1) ACS diagnosis codes (keyword-based match in d_icd_diagnoses.long_title)
acs_diag_codes AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE REGEXP_CONTAINS(
    LOWER(long_title),
    r'(acute myocardial infarction|acute coronary syndrome|unstable angina|st[- ]?elevation|non[- ]st[- ]?elevation|myocardial infarction)'
  )
),

-- 2) Admissions for female patients aged 77-87 that have any ACS code; classify primary vs secondary
acs_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1 AS stay_days,
    -- determine if any ACS diagnosis is primary (seq_num = 1)
    CASE
      WHEN MAX(CASE WHEN di.seq_num = 1 THEN 1 ELSE 0 END) = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  JOIN acs_diag_codes ac
    ON di.icd_code = ac.icd_code AND di.icd_version = ac.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 77 AND 87
  GROUP BY a.subject_id, a.hadm_id, a.admittime, a.dischtime, stay_days
),

-- 3) Imaging events from hcpcsevents (hospital billed codes)
hcpcs_imaging AS (
  SELECT
    hadm_id,
    1 AS evt_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents`
  WHERE LOWER(COALESCE(short_description, '')) LIKE '%ct%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%computed tomography%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%x-ray%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%xray%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%radiograph%'
     OR LOWER(COALESCE(short_description, '')) LIKE '%radiography%'
),

-- 4) Imaging events from ICU procedureevents via d_items labels
icu_procedure_imaging AS (
  SELECT
    pe.hadm_id,
    1 AS evt_count
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON pe.itemid = di.itemid
  WHERE REGEXP_CONTAINS(LOWER(COALESCE(di.label, '')), r'(\\bct\\b|computed tomography|x-?ray|xray|radiograph|radiography)')
     OR REGEXP_CONTAINS(LOWER(COALESCE(pe.ordercategoryname, '')), r'(\\bct\\b|computed tomography|x-?ray|xray|radiograph|radiography)')
),

-- 5) Union imaging events and aggregate per admission
imaging_counts AS (
  SELECT
    hadm_id,
    SUM(evt_count) AS imaging_count
  FROM (
    SELECT * FROM hcpcs_imaging
    UNION ALL
    SELECT * FROM icu_procedure_imaging
  )
  GROUP BY hadm_id
),

-- 6) Combine cohort admissions with imaging counts and bucket stays
cohort_with_counts AS (
  SELECT
    a.*,
    COALESCE(ic.imaging_count, 0) AS imaging_count,
    CASE
      WHEN a.stay_days BETWEEN 1 AND 4 THEN '1-4'
      WHEN a.stay_days BETWEEN 5 AND 8 THEN '5-8'
      ELSE NULL
    END AS stay_bucket
  FROM acs_admissions a
  LEFT JOIN imaging_counts ic
    ON a.hadm_id = ic.hadm_id
  WHERE (DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) + 1) BETWEEN 1 AND 8
)

-- Final aggregation: mean, min, max imaging counts by diagnosis_type and stay_bucket
SELECT
  diagnosis_type,
  stay_bucket,
  COUNT(*) AS n_admissions,
  ROUND(AVG(imaging_count), 2) AS mean_imaging_count,
  MIN(imaging_count) AS min_imaging_count,
  MAX(imaging_count) AS max_imaging_count
FROM cohort_with_counts
GROUP BY diagnosis_type, stay_bucket
ORDER BY diagnosis_type, stay_bucket;