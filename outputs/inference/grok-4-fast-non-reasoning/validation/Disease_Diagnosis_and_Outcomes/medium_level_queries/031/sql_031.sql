WITH qualifying_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.deathtime,
    EXTRACT(DAY FROM TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS los_days,
    CASE 
      WHEN di.icd_code = 'R65.21' THEN 'Septic Shock'
      WHEN di.icd_code LIKE 'A41%' OR di.icd_code = 'R65.2' THEN 'Sepsis'
    END AS condition_group,
    CASE 
      WHEN a.hospital_expire_flag = 1 AND a.deathtime IS NOT NULL 
      THEN EXTRACT(DAY FROM TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY))
      ELSE NULL 
    END AS time_to_death_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND di.icd_version = '10'
    AND di.seq_num = 1
    AND (di.icd_code LIKE 'A41%' OR di.icd_code IN ('R65.2', 'R65.21'))
    AND a.dischtime IS NOT NULL
    AND EXTRACT(DAY FROM TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) >= 0
),
stratified_data AS (
  SELECT 
    condition_group,
    CASE 
      WHEN los_days <= 7 THEN 'LOS <=7 days'
      ELSE 'LOS >7 days'
    END AS los_bin,
    COUNT(*) AS n,
    SAFE_DIVIDE(SUM(hospital_expire_flag), COUNT(*)) * 100 AS mortality_pct,
    -- Median TTD for non-survivors in this stratum
    PERCENTILE_CONT(time_to_death_days, 0.5) IGNORE NULLS
      OVER (PARTITION BY condition_group, 
            CASE WHEN los_days <= 7 THEN 'LOS <=7 days' ELSE 'LOS >7 days' END) AS median_ttd
  FROM qualifying_admissions
  WHERE condition_group IS NOT NULL  -- Ensure valid conditions
  GROUP BY condition_group, los_bin, median_ttd  -- Include median_ttd to avoid aggregation conflict
),
results AS (
  SELECT 
    los_bin,
    MAX(CASE WHEN condition_group = 'Sepsis' THEN n END) AS sepsis_n,
    MAX(CASE WHEN condition_group = 'Septic Shock' THEN n END) AS shock_n,
    MAX(CASE WHEN condition_group = 'Sepsis' THEN mortality_pct END) AS sepsis_mortality_pct,
    MAX(CASE WHEN condition_group = 'Septic Shock' THEN mortality_pct END) AS shock_mortality_pct,
    MAX(CASE WHEN condition_group = 'Sepsis' THEN median_ttd END) AS sepsis_median_ttd,
    MAX(CASE WHEN condition_group = 'Septic Shock' THEN median_ttd END) AS shock_median_ttd
  FROM stratified_data
  GROUP BY los_bin
)
SELECT 
  los_bin,
  sepsis_n AS sepsis_n,
  shock_n AS shock_n,
  sepsis_mortality_pct AS sepsis_mortality_pct,
  shock_mortality_pct AS shock_mortality_pct,
  sepsis_median_ttd AS sepsis_median_ttd,
  shock_median_ttd AS shock_median_ttd,
  (sepsis_mortality_pct - shock_mortality_pct) AS absolute_mortality_diff_pct,
  SAFE_DIVIDE((sepsis_mortality_pct - shock_mortality_pct), shock_mortality_pct) * 100 AS relative_mortality_diff_pct
FROM results
ORDER BY 
  CASE WHEN los_bin = 'LOS <=7 days' THEN 1 ELSE 2 END;