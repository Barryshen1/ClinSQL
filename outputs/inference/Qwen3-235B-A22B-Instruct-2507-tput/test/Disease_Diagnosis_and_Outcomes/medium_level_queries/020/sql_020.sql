WITH sepsis_admissions AS (
  SELECT DISTINCT adm.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag
    ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE diag.icd_version = 10
    AND d_diag.long_title LIKE 'Sepsis%'
    AND NOT (d_diag.icd_code = 'R6521')  -- Exclude septic shock (ICD-10: R65.21)
),
patient_admissions AS (
  SELECT
    p.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    -- Compute actual age at admission
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission,
    -- Check if ICU stay started within 24 hours of admission
    CASE WHEN icu.intime IS NOT NULL THEN 1 ELSE 0 END AS icu_day1,
    -- Calculate LOS in days
    DATETIME_DIFF(adm.dischtime, adm.admittime, DAY) AS los_days,
    -- Days to death (if in-hospital death)
    DATETIME_DIFF(adm.deathtime, adm.admittime, DAY) AS days_to_death
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON p.subject_id = adm.subject_id
  JOIN sepsis_admissions sa
    ON adm.hadm_id = sa.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON adm.hadm_id = icu.hadm_id
    AND icu.intime <= DATETIME_ADD(adm.admittime, INTERVAL 1 DAY)
    AND icu.intime >= adm.admittime
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year)) BETWEEN 86 AND 96
),
grouped_data AS (
  SELECT
    icu_day1,
    CASE
      WHEN los_days <= 3 THEN '≤3'
      WHEN los_days BETWEEN 4 AND 6 THEN '4–6'
      WHEN los_days BETWEEN 7 AND 10 THEN '7–10'
      WHEN los_days > 10 THEN '>10'
      ELSE NULL
    END AS los_group,
    hospital_expire_flag,
    days_to_death
  FROM patient_admissions
  WHERE los_days IS NOT NULL
)
SELECT
  los_group,
  icu_day1,
  COUNT(*) AS n,
  ROUND(AVG(hospital_expire_flag) * 100, 2) AS mortality_rate_pct,
  ROUND(PERCENTILE_CONT(days_to_death, 0.5) OVER (PARTITION BY los_group, icu_day1), 2) AS median_days_to_death
FROM grouped_data
WHERE hospital_expire_flag = 1  -- Only for median days to death, but we want all rows for mortality rate
GROUP BY los_group, icu_day1, days_to_death  -- Required for window function, but we'll adjust
-- Instead, compute median separately and join;