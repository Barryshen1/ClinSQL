WITH
tia_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%transient ischemic attack%'
),
imaging_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp.d_hcpcs`
  WHERE LOWER(long_description) LIKE '%computed tomography%'
     OR LOWER(long_description) LIKE '%magnetic resonance%'
),
tia_admissions AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN tia_codes t
    ON d.icd_code = t.icd_code AND d.icd_version = t.icd_version
),
filtered_patients AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    -- Compute age at admission
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age,
    -- Hospital LOS in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_hospital
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.hadm_id IN (SELECT hadm_id FROM tia_admissions)
    -- Filter age: 88 to 98
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 88 AND 98
    -- Filter hospital LOS: 1 to 7 days
    AND DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
),
icu_flag AS (
  SELECT 
    hadm_id,
    MAX(CASE WHEN stay_id IS NOT NULL THEN 1 ELSE 0 END) AS icu_use
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
),
imaging_counts AS (
  SELECT 
    h.hadm_id,
    COUNT(*) AS imaging_count
  FROM `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
  INNER JOIN imaging_codes i
    ON h.hcpcs_cd = i.code
  GROUP BY h.hadm_id
),
combined AS (
  SELECT 
    f.hadm_id,
    f.los_hospital,
    COALESCE(i.icu_use, 0) AS icu_use,
    COALESCE(ic.imaging_count, 0) AS imaging_count
  FROM filtered_patients f
  LEFT JOIN icu_flag i
    ON f.hadm_id = i.hadm_id
  LEFT JOIN imaging_counts ic
    ON f.hadm_id = ic.hadm_id
),
grouped AS (
  SELECT 
    icu_use,
    CASE 
      WHEN los_hospital BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_hospital BETWEEN 4 AND 7 THEN '4-7'
    END AS los_group,
    imaging_count
  FROM combined
)
SELECT 
  icu_use,
  los_group,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(500)] AS median,
  APPROX_QUANTILES(imaging_count, 1000)[OFFSET(750)] - APPROX_QUANTILES(imaging_count, 1000)[OFFSET(250)] AS iqr
FROM grouped
GROUP BY icu_use, los_group
ORDER BY icu_use, los_group;