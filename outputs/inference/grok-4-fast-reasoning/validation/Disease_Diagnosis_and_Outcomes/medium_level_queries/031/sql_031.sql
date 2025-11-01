WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F' 
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 53 AND 63
    AND a.hadm_id IS NOT NULL
),
has_sepsis AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN (
      (di.icd_version = 9 AND di.icd_code IN ('99591', '99592')) OR
      (di.icd_version = 10 AND (di.icd_code LIKE 'A41%' OR di.icd_code = 'R65.20'))
    ) THEN 1 ELSE 0 END) AS has_sepsis_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON c.hadm_id = di.hadm_id
  GROUP BY c.hadm_id
),
has_shock AS (
  SELECT 
    c.hadm_id,
    MAX(CASE WHEN (
      (di.icd_version = 9 AND di.icd_code = '78552') OR
      (di.icd_version = 10 AND di.icd_code = 'R65.21')
    ) THEN 1 ELSE 0 END) AS has_shock_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON c.hadm_id = di.hadm_id
  GROUP BY c.hadm_id
),
qualified_cohort AS (
  SELECT 
    c.*,
    hs.has_sepsis_flag,
    hsh.has_shock_flag,
    CASE 
      WHEN hs.has_sepsis_flag = 1 AND hsh.has_shock_flag = 0 THEN 'Sepsis'
      WHEN hsh.has_shock_flag = 1 THEN 'Septic Shock'
    END AS condition_group,
    CASE WHEN c.los_days <= 7 THEN '<=7' ELSE '>7' END AS los_stratum
  FROM cohort c
  INNER JOIN has_sepsis hs ON c.hadm_id = hs.hadm_id
  INNER JOIN has_shock hsh ON c.hadm_id = hsh.hadm_id
  WHERE (hs.has_sepsis_flag = 1 AND hsh.has_shock_flag = 0) OR hsh.has_shock_flag = 1
),
deaths AS (
  SELECT 
    TIMESTAMP_DIFF(deathtime, admittime, HOUR) / 24.0 AS ttd_days,
    condition_group,
    los_stratum
  FROM qualified_cohort
  WHERE hospital_expire_flag = 1 AND deathtime IS NOT NULL
),
medians AS (
  SELECT 
    condition_group,
    los_stratum,
    PERCENTILE_CONT(ttd_days, 0.5) AS median_ttd_days
  FROM deaths
  GROUP BY condition_group, los_stratum
),
summary AS (
  SELECT 
    c.condition_group,
    c.los_stratum,
    COUNT(*) AS N,
    SUM(c.hospital_expire_flag) AS num_deaths,
    ROUND(100.0 * SUM(c.hospital_expire_flag) / COUNT(*), 2) AS mortality_pct,
    ANY_VALUE(m.median_ttd_days) AS median_ttd_days
  FROM qualified_cohort c
  LEFT JOIN medians m 
    ON c.condition_group = m.condition_group 
    AND c.los_stratum = m.los_stratum
  GROUP BY c.condition_group, c.los_stratum
)
SELECT 
  s.los_stratum,
  MAX(CASE WHEN s.condition_group = 'Sepsis' THEN s.N END) AS sepsis_N,
  MAX(CASE WHEN s.condition_group = 'Septic Shock' THEN s.N END) AS shock_N,
  MAX(CASE WHEN s.condition_group = 'Sepsis' THEN s.mortality_pct END) AS sepsis_mortality_pct,
  MAX(CASE WHEN s.condition_group = 'Septic Shock' THEN s.mortality_pct END) AS shock_mortality_pct,
  MAX(CASE WHEN s.condition_group = 'Sepsis' THEN s.median_ttd_days END) AS sepsis_median_ttd_days,
  MAX(CASE WHEN s.condition_group = 'Septic Shock' THEN s.median_ttd_days END) AS shock_median_ttd_days,
  (MAX(CASE WHEN s.condition_group = 'Septic Shock' THEN s.mortality_pct END) - 
   MAX(CASE WHEN s.condition_group = 'Sepsis' THEN s.mortality_pct END)) AS abs_mort_diff_pct,
  ROUND(
    (MAX(CASE WHEN s.condition_group = 'Septic Shock' THEN s.mortality_pct END) - 
     MAX(CASE WHEN s.condition_group = 'Sepsis' THEN s.mortality_pct END)) / 
    NULLIF(MAX(CASE WHEN s.condition_group = 'Sepsis' THEN s.mortality_pct END), 0) * 100, 2
  ) AS rel_mort_diff_pct
FROM summary s
GROUP BY s.los_stratum
ORDER BY 
  CASE WHEN los_stratum = '<=7' THEN 1 ELSE 2 END;