WITH cohort AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    CASE 
      WHEN di.icd_code IN ('995.91', 'R65.20') AND di2.icd_code IS NULL THEN 'sepsis_only'
      WHEN di2.icd_code IN ('785.52', 'R65.21') THEN 'septic_shock'
    END AS condition,
    EXTRACT(EPOCH FROM (a.dischtime - a.admittime)) / 86400 AS los_days,
    CASE 
      WHEN EXTRACT(EPOCH FROM (a.dischtime - a.admittime)) / 86400 <= 7 THEN '≤7'
      ELSE '>7'
    END AS los_group,
    CASE 
      WHEN a.deathtime IS NOT NULL 
      THEN EXTRACT(EPOCH FROM (a.deathtime - a.admittime)) / 86400 
    END AS time_to_death_days
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
    AND di.icd_code IN ('995.91', 'R65.20')
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd di2
    ON a.hadm_id = di2.hadm_id
    AND di2.icd_code IN ('785.52', 'R65.21')
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 53 AND 63
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (di.icd_code IS NOT NULL OR di2.icd_code IS NOT NULL)
),
grouped AS (
  SELECT
    condition,
    los_group,
    COUNT(*) AS n,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct,
    PERCENTILE_CONT(time_to_death_days, 0.5) AS median_time_to_death_days
  FROM cohort
  WHERE condition IS NOT NULL
  GROUP BY condition, los_group
),
differences AS (
  SELECT
    g1.condition,
    g1.los_group,
    g1.n,
    g1.mortality_pct,
    g1.median_time_to_death_days,
    g1.mortality_pct - g2.mortality_pct AS absolute_diff,
    (g1.mortality_pct / g2.mortality_pct) - 1 AS relative_diff
  FROM grouped g1
  INNER JOIN grouped g2
    ON g1.condition = g2.condition
    AND g1.los_group = '≤7'
    AND g2.los_group = '>7'
)
SELECT
  condition,
  los_group,
  n,
  mortality_pct,
  median_time_to_death_days,
  absolute_diff,
  relative_diff
FROM differences
UNION ALL
SELECT
  condition,
  los_group,
  n,
  mortality_pct,
  median_time_to_death_days,
  NULL AS absolute_diff,
  NULL AS relative_diff
FROM grouped
WHERE los_group = '>7'
ORDER BY condition, los_group;