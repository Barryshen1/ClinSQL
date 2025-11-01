WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    a.admission_type,
    DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 AS los_days,
    CASE 
      WHEN DATE_DIFF(a.dischtime, a.admittime, DAY) + 1 < 8 THEN 'LOS < 8 days'
      ELSE 'LOS ≥ 8 days'
    END AS los_group
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE 
    p.anchor_age BETWEEN 50 AND 60
    AND p.gender = 'M'
    AND a.admission_type != 'NEWBORN'
    AND (
      -- Sepsis ICD-10
      (d.icd_version = '10' AND REGEXP_CONTAINS(d.icd_code, r'^A41'))
      OR 
      -- Sepsis ICD-9
      (d.icd_version = '9' AND REGEXP_CONTAINS(d.icd_code, r'^038[.]?'))
    )
    -- Exclude any admission with septic shock
    AND NOT EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d_shock
      WHERE d_shock.subject_id = a.subject_id 
        AND d_shock.hadm_id = a.hadm_id
        AND (
          (d_shock.icd_version = '10' AND REGEXP_CONTAINS(d_shock.icd_code, r'^R65\.2'))
          OR 
          (d_shock.icd_version = '9' AND d_shock.icd_code = '785.52')
        )
    )
),
ranked_cohort AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY admittime) AS rn
  FROM cohort
),
base_cohort AS (
  SELECT * 
  FROM ranked_cohort 
  WHERE rn = 1
),
mortality_stats AS (
  SELECT 
    los_group,
    COUNT(*) AS n_total,
    SUM(CAST(hospital_expire_flag AS INT64)) AS n_deaths,
    SAFE_CAST(SUM(CAST(hospital_expire_flag AS INT64)) * 100.0 / COUNT(*) AS NUMERIC) AS mortality_pct
  FROM base_cohort
  GROUP BY los_group
),
ci_stats AS (
  SELECT 
    los_group,
    n_total,
    n_deaths,
    -- Wilson score 95% CI lower bound
    GREATEST(0, 
      ((n_deaths / CAST(n_total AS FLOAT64)) + (1.96 * 1.96) / (2 * n_total) - 
       1.96 * SQRT(((n_deaths / CAST(n_total AS FLOAT64)) * (1 - n_deaths / CAST(n_total AS FLOAT64)) / n_total) + 
                   (1.96 * 1.96) / (4 * n_total * n_total))) / 
      (1 + 1.96 * 1.96 / n_total)
    ) * 100 AS ci_lower_pct,
    -- Wilson score 95% CI upper bound
    LEAST(100, 
      ((n_deaths / CAST(n_total AS FLOAT64)) + (1.96 * 1.96) / (2 * n_total) + 
       1.96 * SQRT(((n_deaths / CAST(n_total AS FLOAT64)) * (1 - n_deaths / CAST(n_total AS FLOAT64)) / n_total) + 
                   (1.96 * 1.96) / (4 * n_total * n_total))) / 
      (1 + 1.96 * 1.96 / n_total)
    ) * 100 AS ci_upper_pct
  FROM mortality_stats
),
median_ttd AS (
  SELECT 
    los_group,
    APPROX_QUANTILES(SAFE.DATE_DIFF(deathtime, admittime, DAY), 2, 0.5)[OFFSET(1)] AS median_days
  FROM base_cohort
  WHERE hospital_expire_flag = 1 
    AND deathtime IS NOT NULL
  GROUP BY los_group
)
SELECT 
  m.los_group,
  m.n_total,
  m.n_deaths,
  ROUND(m.mortality_pct, 2) AS mortality_pct,
  ROUND(c.ci_lower_pct, 2) AS ci_lower_pct,
  ROUND(c.ci_upper_pct, 2) AS ci_upper_pct,
  ROUND(COALESCE(t.median_days, NULL), 1) AS median_ttd_days
FROM mortality_stats m
INNER JOIN ci_stats c ON m.los_group = c.los_group
LEFT JOIN median_ttd t ON m.los_group = t.los_group
ORDER BY 
  CASE los_group 
    WHEN 'LOS < 8 days' THEN 1 
    ELSE 2 
  END;