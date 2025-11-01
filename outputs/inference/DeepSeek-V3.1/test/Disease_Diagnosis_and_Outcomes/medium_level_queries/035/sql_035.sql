WITH gi_bleed_cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    pat.anchor_age,
    -- Classify GI bleed type
    MAX(CASE WHEN diag.icd_code IN ('K92.0','K92.1','K92.2','K25.0','K25.2','K25.4','K25.6','K26.0','K26.2','K26.4','K26.6','K27.0','K27.2','K27.4','K27.6','K28.0','K28.2','K28.4','K28.6') THEN 1 ELSE 0 END) AS upper_gi_bleed,
    MAX(CASE WHEN diag.icd_code IN ('K62.5','K92.1','I85.01','I85.11','K57.11','K57.12','K57.13','K57.21','K57.22','K57.23','K57.31','K57.32','K57.33','K57.41','K57.42','K57.43','K57.51','K57.52','K57.53','K57.81','K57.82','K57.83','K57.91','K57.92','K57.93','K62.5','K92.1') THEN 1 ELSE 0 END) AS lower_gi_bleed
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.subject_id = diag.subject_id AND adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 69 AND 79
    AND (
      diag.icd_code IN ('K92.0','K92.1','K92.2','K25.0','K25.2','K25.4','K25.6','K26.0','K26.2','K26.4','K26.6','K27.0','K27.2','K27.4','K27.6','K28.0','K28.2','K28.4','K28.6')
      OR diag.icd_code IN ('K62.5','K92.1','I85.01','I85.11','K57.11','K57.12','K57.13','K57.21','K57.22','K57.23','K57.31','K57.32','K57.33','K57.41','K57.42','K57.43','K57.51','K57.52','K57.53','K57.81','K57.82','K57.83','K57.91','K57.92','K57.93','K62.5','K92.1')
    )
  GROUP BY adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime, adm.hospital_expire_flag, pat.anchor_age
),

-- Add LOS group and ICU flags
cohort_with_features AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.upper_gi_bleed,
    c.lower_gi_bleed,
    c.hospital_expire_flag AS mortality,
    -- Calculate LOS and group
    DATE_DIFF(c.dischtime, c.admittime, DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) + 1 BETWEEN 1 AND 2 THEN '1-2'
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) + 1 BETWEEN 3 AND 5 THEN '3-5'
      WHEN DATE_DIFF(c.dischtime, c.admittime, DAY) + 1 BETWEEN 6 AND 9 THEN '6-9'
      ELSE '>=10'
    END AS los_group,
    -- Check if had any ICU stay
    CASE WHEN icu.stay_id IS NOT NULL THEN 1 ELSE 0 END AS ever_icu,
    -- Check if in ICU within first 24h of admission
    CASE WHEN icu1.stay_id IS NOT NULL THEN 1 ELSE 0 END AS icu_day1
  FROM gi_bleed_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON c.hadm_id = icu.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu1
    ON c.hadm_id = icu1.hadm_id 
    AND icu1.intime <= DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
)

-- Aggregate by LOS group and day1 ICU status
SELECT 
  CASE WHEN upper_gi_bleed = 1 THEN 'Upper GI' ELSE 'Lower GI' END AS gi_type,
  los_group,
  icu_day1,
  COUNT(*) AS n_admissions,
  SUM(ever_icu) AS n_icu_admissions,
  ROUND(SUM(ever_icu) * 100.0 / COUNT(*), 2) AS icu_admission_rate,
  SUM(mortality) AS n_deaths,
  ROUND(SUM(mortality) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM cohort_with_features
WHERE upper_gi_bleed = 1 OR lower_gi_bleed = 1
GROUP BY gi_type, los_group, icu_day1
ORDER BY gi_type, los_group, icu_day1;