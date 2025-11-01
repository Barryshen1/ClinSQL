WITH base_population AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    -- Calculate age at admission using MIMIC-IV methodology
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    -- Calculate hospital LOS in days (calendar days)
    DATE_DIFF(CAST(a.dischtime AS DATE), CAST(a.admittime AS DATE), DAY) AS los_days,
    -- Determine if patient was in ICU on day 1 (first 24 hours)
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = a.hadm_id 
          AND i.intime < DATETIME_ADD(a.admittime, INTERVAL 1 DAY)
      ) THEN 'Yes' 
      ELSE 'No' 
    END AS icu_day1
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),
sepsis_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND (icd_code LIKE 'A40%' OR icd_code LIKE 'A41%')
  GROUP BY hadm_id
),
septic_shock_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 10
    AND icd_code = 'R6521'
  GROUP BY hadm_id
),
sepsis_cohort AS (
  SELECT 
    bp.*
  FROM base_population bp
  WHERE 
    bp.gender = 'M'
    AND bp.age_at_admission BETWEEN 86 AND 96
    AND bp.hadm_id IN (SELECT hadm_id FROM sepsis_admissions)
    AND bp.hadm_id NOT IN (SELECT hadm_id FROM septic_shock_admissions)
),
with_days_to_death AS (
  SELECT 
    *,
    -- Calculate days to death for deceased patients only
    CASE WHEN hospital_expire_flag = 1 
         THEN DATE_DIFF(CAST(deathtime AS DATE), CAST(admittime AS DATE), DAY) 
         ELSE NULL 
    END AS days_to_death
  FROM sepsis_cohort
),
grouped_results AS (
  SELECT 
    CASE 
      WHEN los_days <= 3 THEN '≤3'
      WHEN los_days BETWEEN 4 AND 6 THEN '4-6'
      WHEN los_days BETWEEN 7 AND 10 THEN '7-10'
      ELSE '>10'
    END AS los_group,
    icu_day1,
    COUNT(*) AS n,
    SUM(hospital_expire_flag) AS deaths,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_rate
  FROM with_days_to_death
  GROUP BY los_group, icu_day1
),
median_days AS (
  SELECT 
    APPROX_QUANTILES(days_to_death, 100)[OFFSET(50)] AS median_days_to_death
  FROM with_days_to_death
  WHERE days_to_death IS NOT NULL
)
SELECT 
  g.*,
  m.median_days_to_death
FROM grouped_results g
CROSS JOIN median_days m
ORDER BY 
  CASE los_group
    WHEN '≤3' THEN 1
    WHEN '4-6' THEN 2
    WHEN '7-10' THEN 3
    ELSE 4
  END,
  icu_day1;