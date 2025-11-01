WITH patient_admissions AS (
  SELECT
    a.hadm_id,
    p.subject_id,
    p.gender,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime,
    -- Length of stay in days
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    -- Flag ICU use
    CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS had_icu,
    -- LOS group
    CASE
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN DATETIME_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 4 AND 7 THEN '4-7 days'
      ELSE NULL
    END AS los_group
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu`.icustays icu
    ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 88 AND 98
    AND a.admittime <= a.dischtime
),
tia_admissions AS (
  SELECT DISTINCT pa.*
  FROM patient_admissions pa
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diag
    ON pa.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE LOWER(d_diag.long_title) LIKE '%transient ischemic%'
     OR d_diag.icd_code = 'G45.9'  -- Common TIA code
),
imaging_codes AS (
  SELECT code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_hcpcs
  WHERE (
    LOWER(short_description) LIKE '%ct%' AND LOWER(short_description) LIKE '%head%'
    OR LOWER(short_description) LIKE '%mri%' AND LOWER(short_description) LIKE '%brain%'
    OR LOWER(short_description) LIKE '%magnetic resonance%' AND LOWER(short_description) LIKE '%head%'
    OR LOWER(short_description) LIKE '%computed tomography%' AND LOWER(short_description) LIKE '%head%'
  )
),
admission_imaging_counts AS (
  SELECT
    ta.hadm_id,
    ta.los_group,
    ta.had_icu,
    COUNT(hc.chartdate) AS imaging_count
  FROM tia_admissions ta
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.hcpcsevents hc
    ON ta.hadm_id = hc.hadm_id
    AND hc.chartdate >= ta.admittime
    AND hc.chartdate <= ta.dischtime
  LEFT JOIN imaging_codes ic
    ON hc.hcpcs_cd = ic.code
  WHERE ta.los_group IS NOT NULL
  GROUP BY ta.hadm_id, ta.los_group, ta.had_icu
)
SELECT
  los_group,
  had_icu,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(50)] AS median_imaging_count,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS q3,
  -- Format IQR as string
  CONCAT(
    CAST(APPROX_QUANTILES(imaging_count, 100)[OFFSET(25)] AS STRING),
    ' - ',
    CAST(APPROX_QUANTILES(imaging_count, 100)[OFFSET(75)] AS STRING)
  ) AS iqr_imaging_count
FROM admission_imaging_counts
GROUP BY los_group, had_icu
ORDER BY los_group, had_icu;