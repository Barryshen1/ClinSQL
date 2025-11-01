WITH patient_cohort AS (
  -- Base cohort: female, 44-54, with principal TIA diagnosis
  SELECT DISTINCT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 44 AND 54
    AND d.seq_num = 1
    AND d.icd_version = '10'
    AND d.icd_code = 'G45.9'
    AND p.dod IS NULL  -- Exclude deceased without admissions
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 BETWEEN 1 AND 7
),

icu_flag AS (
  -- Add ICU use flag per admission
  SELECT 
    pc.*,
    CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_used
  FROM 
    patient_cohort pc
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON pc.hadm_id = icu.hadm_id
),

imaging_per_adm AS (
  -- Count distinct diagnostic imaging HCPCS per admission
  SELECT 
    pc.hadm_id,
    COUNT(DISTINCT h.hcpcs_cd) AS imaging_count
  FROM 
    patient_cohort pc
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.hcpcsevents` h
    ON pc.hadm_id = h.hadm_id
  WHERE 
    h.hcpcs_cd IN (
      '70450', '70460', '70470',  -- CT Head
      '70540', '70541', '70542', '70543', '70544', '70545', '70546', '70547', '70548', '70549', '70551', '70552', '70553',  -- MRI Head/Neck
      '93880',  -- Carotid US
      '93306', '93307', '93308', '93350'  -- Echo
    )
  GROUP BY 
    pc.hadm_id
),

stratified_imaging AS (
  -- Combine with LOS/ICU groups, default to 0 imaging if none
  SELECT 
    if.los_days,
    CASE 
      WHEN if.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN if.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END AS los_group,
    if.icu_used,
    COALESCE(ia.imaging_count, 0) AS imaging_count
  FROM 
    icu_flag if
  LEFT JOIN 
    imaging_per_adm ia
    ON if.hadm_id = ia.hadm_id
  WHERE 
    CASE 
      WHEN if.los_days BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN if.los_days BETWEEN 5 AND 7 THEN '5-7 days'
    END IS NOT NULL
)

-- Compute percentiles by group
SELECT DISTINCT
  los_group,
  icu_used,
  PERCENTILE_CONT(imaging_count, 0.25) OVER (PARTITION BY los_group, icu_used) AS p25,
  PERCENTILE_CONT(imaging_count, 0.50) OVER (PARTITION BY los_group, icu_used) AS p50,
  PERCENTILE_CONT(imaging_count, 0.75) OVER (PARTITION BY los_group, icu_used) AS p75
FROM 
  stratified_imaging
ORDER BY 
  los_group, icu_used;