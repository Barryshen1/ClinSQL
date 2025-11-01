WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    p.gender,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 44 AND 54
),
tia_admissions AS (
  SELECT DISTINCT pa.hadm_id
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON pa.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%transient ischemic attack%'
     OR LOWER(d.long_title) LIKE '%tia%'
     OR d.icd_code IN ('G45.9', 'G45.8', 'G45.0', 'G45.1', 'G45.2', 'G45.3', 'G45.4')
),
imaging_procs AS (
  SELECT
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  JOIN `physionet-data.mimiciv_3_1_hosp.d_hcpcs` d
    ON h.hcpcs_cd = d.code
  WHERE d.category = 2  -- Corrected: category is INT64, 2 = Diagnostic Imaging
    OR LOWER(d.short_description) LIKE '%ct%'
    OR LOWER(d.short_description) LIKE '%mri%'
    OR LOWER(d.short_description) LIKE '%angiogram%'
    OR LOWER(d.short_description) LIKE '%ultrasound%'
    OR LOWER(d.short_description) LIKE '%echo%'
  GROUP BY h.hadm_id
),
admission_groups AS (
  SELECT
    pa.hadm_id,
    pa.los_days,
    CASE
      WHEN i.stay_id IS NOT NULL THEN 1
      ELSE 0
    END AS icu_used,
    COALESCE(ip.imaging_count, 0) AS imaging_count
  FROM patient_admissions pa
  JOIN tia_admissions tia ON pa.hadm_id = tia.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON pa.hadm_id = i.hadm_id
  LEFT JOIN imaging_procs ip
    ON pa.hadm_id = ip.hadm_id
  WHERE pa.los_days BETWEEN 1 AND 7
),
grouped_stats AS (
  SELECT
    CASE
      WHEN los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    CASE WHEN icu_used = 1 THEN 'Yes' ELSE 'No' END AS icu_use,
    imaging_count
  FROM admission_groups
)
SELECT
  los_group,
  icu_use,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS p25_imaging,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS p50_imaging,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS p75_imaging
FROM grouped_stats
GROUP BY los_group, icu_use
ORDER BY los_group, icu_use;