WITH hf_cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND (
      (d.icd_code LIKE '428%' AND d.icd_version = 9)
      OR (d.icd_code LIKE 'I50.%' AND d.icd_version = 10)
    )
    AND (a.deathtime IS NULL OR a.deathtime >= a.admittime)
    AND DATE_DIFF(a.dischtime, a.admittime, DAY) > 0
),
los_groups AS (
  SELECT 
    *,
    CASE 
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7'
      ELSE '>=8'
    END AS los_group
  FROM hf_cohort
),
summary AS (
  SELECT 
    los_group,
    COUNT(*) AS n_total,
    COUNTIF(hospital_expire_flag = 1) AS n_deaths,
    SAFE_DIVIDE(COUNTIF(hospital_expire_flag = 1), COUNT(*)) * 100 AS mortality_pct
  FROM los_groups
  GROUP BY los_group
),
time_to_death AS (
  SELECT 
    los_group,
    DATE_DIFF(deathtime, admittime, HOUR) / 24.0 AS days_to_death
  FROM los_groups
  WHERE hospital_expire_flag = 1
),
median_tod AS (
  SELECT 
    los_group,
    PERCENTILE_CONT(0.5) OVER (ORDER BY days_to_death) AS median_days_to_death
  FROM time_to_death
),
ci_calc AS (
  SELECT 
    los_group,
    1.96 * SQRT(p * (1 - p) / n + (1.96 * 1.96) / (4 * n * n)) / (1 + (1.96 * 1.96) / n) AS ci_half_width
  FROM (
    SELECT 
      los_group,
      SAFE_DIVIDE(n_deaths, n_total) AS p,
      n_total AS n
    FROM summary
  )
)
SELECT 
  s.los_group,
  s.n_total,
  s.n_deaths,
  ROUND(s.mortality_pct, 2) AS mortality_pct,
  ROUND(s.mortality_pct - ci.ci_half_width * 100, 2) AS ci_lower,
  ROUND(s.mortality_pct + ci.ci_half_width * 100, 2) AS ci_upper,
  ROUND(mt.median_days_to_death, 1) AS median_tod_days
FROM summary s
INNER JOIN ci_calc ci ON s.los_group = ci.los_group
LEFT JOIN median_tod mt ON s.los_group = mt.los_group
ORDER BY 
  CASE s.los_group
    WHEN '1-3' THEN 1
    WHEN '4-7' THEN 2
    ELSE 3
  END;