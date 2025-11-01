WITH sepsis_codes AS (
  SELECT 'A40' AS code, 'sepsis' AS type UNION ALL
  SELECT 'A41', 'sepsis' UNION ALL
  SELECT 'R65.20', 'sepsis' UNION ALL
  SELECT 'R65.22', 'sepsis' UNION ALL
  SELECT 'R65.28', 'sepsis' UNION ALL
  SELECT 'R65.29', 'sepsis' UNION ALL
  SELECT 'R65.21', 'septic_shock' UNION ALL
  SELECT 'A40.0', 'septic_shock' UNION ALL
  SELECT 'A40.1', 'septic_shock' UNION ALL
  SELECT 'A41.0', 'septic_shock' UNION ALL
  SELECT 'A41.1', 'septic_shock'
),
base_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 53 AND 63
    AND a.dischtime IS NOT NULL
),
sepsis_flags AS (
  SELECT 
    b.*,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = b.hadm_id
        AND d.icd_version = 10
        AND EXISTS (
          SELECT 1
          FROM sepsis_codes sc
          WHERE sc.type = 'sepsis'
            AND (d.icd_code = sc.code 
                 OR (sc.code IN ('A40','A41') AND d.icd_code LIKE sc.code || '.%'))
        )
    ) AS has_sepsis,
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = b.hadm_id
        AND d.icd_version = 10
        AND EXISTS (
          SELECT 1
          FROM sepsis_codes sc
          WHERE sc.type = 'septic_shock'
            AND d.icd_code = sc.code
        )
    ) AS has_septic_shock
  FROM base_admissions b
),
condition_groups AS (
  SELECT 
    *,
    CASE 
      WHEN has_septic_shock THEN 'septic_shock'
      WHEN has_sepsis THEN 'sepsis'
      ELSE 'other'
    END AS condition_group
  FROM sepsis_flags
),
los_groups AS (
  SELECT 
    *,
    TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(dischtime, admittime, DAY) <= 7 THEN 'LOS<=7'
      ELSE 'LOS>7'
    END AS los_group
  FROM condition_groups
),
non_survivors AS (
  SELECT 
    condition_group,
    los_group,
    los_days AS time_to_death  -- Use precomputed los_days
  FROM los_groups
  WHERE hospital_expire_flag = 1
),
mortality_rates AS (
  SELECT 
    condition_group,
    los_group,
    COUNT(*) AS N,
    AVG(hospital_expire_flag) * 100 AS mortality_rate,
    NULL AS median_time_to_death
  FROM los_groups
  GROUP BY condition_group, los_group
),
medians AS (
  SELECT 
    condition_group,
    los_group,
    PERCENTILE_CONT(time_to_death, 0.5) AS median_time_to_death  -- Fixed PERCENTILE_CONT syntax
  FROM non_survivors
  GROUP BY condition_group, los_group
),
combined AS (
  SELECT 
    m.*,
    COALESCE(md.median_time_to_death, 0) AS median_time_to_death
  FROM mortality_rates m
  LEFT JOIN medians md 
    ON m.condition_group = md.condition_group 
    AND m.los_group = md.los_group
),
pivoted AS (
  SELECT 
    los_group,
    MAX(CASE WHEN condition_group = 'sepsis' THEN N END) AS N_sepsis,
    MAX(CASE WHEN condition_group = 'sepsis' THEN mortality_rate END) AS mortality_rate_sepsis,
    MAX(CASE WHEN condition_group = 'sepsis' THEN median_time_to_death END) AS median_time_to_death_sepsis,
    MAX(CASE WHEN condition_group = 'septic_shock' THEN N END) AS N_septic_shock,
    MAX(CASE WHEN condition_group = 'septic_shock' THEN mortality_rate END) AS mortality_rate_septic_shock,
    MAX(CASE WHEN condition_group = 'septic_shock' THEN median_time_to_death END) AS median_time_to_death_septic_shock
  FROM combined
  WHERE condition_group IN ('sepsis', 'septic_shock')
  GROUP BY los_group
),
differences AS (
  SELECT 
    los_group,
    N_sepsis,
    N_septic_shock,
    mortality_rate_sepsis,
    mortality_rate_septic_shock,
    mortality_rate_septic_shock - mortality_rate_sepsis AS absolute_difference,
    CASE 
      WHEN mortality_rate_sepsis = 0 THEN NULL 
      ELSE (mortality_rate_septic_shock - mortality_rate_sepsis) / mortality_rate_sepsis 
    END AS relative_difference,
    median_time_to_death_sepsis,
    median_time_to_death_septic_shock
  FROM pivoted
)
SELECT 
  los_group,
  'sepsis' AS condition_group,
  N_sepsis AS N,
  mortality_rate_sepsis AS mortality_rate,
  median_time_to_death_sepsis AS median_time_to_death,
  NULL AS absolute_difference,
  NULL AS relative_difference
FROM differences
UNION ALL
SELECT 
  los_group,
  'septic_shock' AS condition_group,
  N_septic_shock AS N,
  mortality_rate_septic_shock AS mortality_rate,
  median_time_to_death_septic_shock AS median_time_to_death,
  NULL AS absolute_difference,
  NULL AS relative_difference
FROM differences
UNION ALL
SELECT 
  los_group,
  'difference' AS condition_group,
  NULL AS N,
  NULL AS mortality_rate,
  NULL AS median_time_to_death,
  absolute_difference,
  relative_difference
FROM differences
ORDER BY los_group, condition_group;