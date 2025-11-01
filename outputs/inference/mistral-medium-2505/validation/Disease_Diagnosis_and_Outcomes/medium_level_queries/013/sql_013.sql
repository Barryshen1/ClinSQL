WITH hf_admissions AS (
  -- Get admissions for women 80-90 with acute decompensated HF
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY) IS NULL THEN NULL
      ELSE TIMESTAMP_DIFF(a.deathtime, a.admittime, DAY)
    END AS time_to_death_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 80 AND 90
    AND d.icd_code IN ('I501', 'I502', 'I503', 'I504', 'I509') -- Acute decompensated HF codes
    AND d.icd_version = 10
),

los_groups AS (
  -- Categorize admissions by LOS
  SELECT
    hadm_id,
    los_days,
    time_to_death_days,
    hospital_expire_flag,
    CASE
      WHEN los_days BETWEEN 1 AND 3 THEN '1-3 days'
      WHEN los_days BETWEEN 4 AND 7 THEN '4-7 days'
      WHEN los_days >= 8 THEN '8+ days'
      ELSE NULL
    END AS los_group
  FROM
    hf_admissions
  WHERE
    los_days IS NOT NULL
),

mortality_stats AS (
  -- Calculate mortality stats by LOS group
  SELECT
    los_group,
    COUNT(*) AS total_admissions,
    SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
    ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 /
          COUNT(*), 2) AS mortality_percentage,
    -- Calculate 95% CI for mortality percentage
    ROUND(1.96 * SQRT((SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 /
          COUNT(*)) * (1 - (SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 1.0 /
          COUNT(*) )) / COUNT(*) ) * 100, 2) AS ci_95
  FROM
    los_groups
  WHERE
    los_group IS NOT NULL
  GROUP BY
    los_group
),

median_times AS (
  -- Pre-calculate median time-to-death for each LOS group
  SELECT
    los_group,
    PERCENTILE_CONT(time_to_death_days, 0.5) OVER(PARTITION BY los_group) AS median_time_to_death
  FROM
    los_groups
  WHERE
    time_to_death_days IS NOT NULL
  GROUP BY
    los_group, time_to_death_days
)

-- Final output with median time-to-death from the pre-calculated CTE
SELECT
  m.los_group,
  m.total_admissions,
  m.deaths,
  m.mortality_percentage,
  CONCAT(ROUND(m.mortality_percentage - m.ci_95, 2), ' - ', ROUND(m.mortality_percentage + m.ci_95, 2)) AS ci_95_range,
  mt.median_time_to_death
FROM
  mortality_stats m
LEFT JOIN
  (SELECT los_group, MAX(median_time_to_death) AS median_time_to_death
   FROM median_times
   GROUP BY los_group) mt
ON m.los_group = mt.los_group
ORDER BY
  CASE m.los_group
    WHEN '1-3 days' THEN 1
    WHEN '4-7 days' THEN 2
    WHEN '8+ days' THEN 3
  END;