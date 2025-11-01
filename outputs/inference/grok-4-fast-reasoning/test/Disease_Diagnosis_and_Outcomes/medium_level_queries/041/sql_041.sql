WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.deathtime, 
    a.hospital_expire_flag,
    p.gender, 
    p.anchor_age,
    p.anchor_year,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.dischtime IS NOT NULL
),

aged_cohort AS (
  SELECT *,
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS admission_age
  FROM cohort
  WHERE anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 50 AND 60
),

sepsis_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = '9' AND (icd_code LIKE '038%' OR icd_code = '995.91'))
     OR (icd_version = '10' AND icd_code LIKE 'A41%')
),

shock_hadm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_code IN ('785.52', 'R65.21')
),

filtered_cohort AS (
  SELECT ac.*
  FROM aged_cohort ac
  INNER JOIN sepsis_hadm s ON ac.hadm_id = s.hadm_id
  LEFT JOIN shock_hadm sh ON ac.hadm_id = sh.hadm_id
  WHERE sh.hadm_id IS NULL
),

short_stay AS (
  SELECT 
    COUNT(*) AS n_total_short,
    COUNTIF(hospital_expire_flag = '1') AS n_died_short,
    SAFE_DIVIDE(COUNTIF(hospital_expire_flag = '1'), COUNT(*)) * 100 AS mortality_short
  FROM filtered_cohort
  WHERE los_days <= 7
),

long_stay AS (
  SELECT 
    COUNT(*) AS n_total_long,
    COUNTIF(hospital_expire_flag = '1') AS n_died_long,
    SAFE_DIVIDE(COUNTIF(hospital_expire_flag = '1'), COUNT(*)) * 100 AS mortality_long
  FROM filtered_cohort
  WHERE los_days > 7
),

median_ttd AS (
  SELECT 
    PERCENTILE_CONT(TIMESTAMP_DIFF(deathtime, admittime, DAY), 0.5) AS median_days_to_death
  FROM filtered_cohort
  WHERE hospital_expire_flag = '1'
)

SELECT 
  s.n_total_short,
  s.n_died_short,
  ROUND(s.mortality_short, 2) AS mortality_pct_leq7,
  l.n_total_long,
  l.n_died_long,
  ROUND(l.mortality_long, 2) AS mortality_pct_gt7,
  ROUND(s.mortality_short - l.mortality_long, 2) AS absolute_difference,
  ROUND(
    CASE 
      WHEN l.mortality_long > 0 THEN (s.mortality_short - l.mortality_long) / l.mortality_long * 100 
      ELSE NULL 
    END, 2
  ) AS relative_difference_pct,
  ROUND(m.median_days_to_death, 2) AS median_time_to_death_days
FROM short_stay s, long_stay l, median_ttd m;