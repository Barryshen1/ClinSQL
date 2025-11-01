WITH base AS (
  -- Select male patients aged 44-54 at admission, exclude ICU stays (general ward)
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON i.hadm_id = a.hadm_id
  WHERE
    UPPER(p.gender) = 'M'
    AND CAST(p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS INT64) BETWEEN 44 AND 54
    AND i.hadm_id IS NULL          -- exclude ICU stays (general ward population)
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
calc AS (
  -- LOS in days
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    discharge_location,
    age_at_admit,
    TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 86400.0 AS los_days
  FROM base
  WHERE dischtime > admittime
),
discharge_group AS (
  -- Map discharge_location to HOME / HOSPICE / DEATH
  SELECT
    hadm_id,
    subject_id,
    admittime,
    dischtime,
    discharge_location,
    los_days,
    CASE
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'HOME'
      WHEN UPPER(discharge_location) LIKE '%HOSPICE%' THEN 'HOSPICE'
      WHEN UPPER(discharge_location) LIKE '%DEATH%' OR UPPER(discharge_location) LIKE '%DIED%' OR UPPER(discharge_location) LIKE '%DOD%' THEN 'DEATH'
      ELSE NULL
    END AS discharge_group
  FROM calc
  WHERE discharge_location IS NOT NULL
),
clean AS (
  -- Keep only the three target groups
  SELECT *
  FROM discharge_group
  WHERE discharge_group IS NOT NULL
),
stats_pcts AS (
  -- LOS percentiles by discharge group
  SELECT
    discharge_group,
    PERCENTILE_CONT(los_days, 0.50) OVER (PARTITION BY discharge_group) AS p50,
    PERCENTILE_CONT(los_days, 0.75) OVER (PARTITION BY discharge_group) AS p75,
    PERCENTILE_CONT(los_days, 0.90) OVER (PARTITION BY discharge_group) AS p90,
    PERCENTILE_CONT(los_days, 0.95) OVER (PARTITION BY discharge_group) AS p95
  FROM clean
),
groups_for_pr AS (
  SELECT DISTINCT discharge_group FROM clean
),
pr_target AS (
  -- Extend with synthetic 7.0-day rows for each group to compute percentile rank for 7 days
  SELECT discharge_group, los_days
  FROM clean
  UNION ALL
  SELECT discharge_group, 7.0 AS los_days
  FROM groups_for_pr
),
pr7 AS (
  SELECT
    discharge_group,
    100 * PERCENT_RANK() OVER (PARTITION BY discharge_group ORDER BY los_days) AS pr_of_7
  FROM pr_target
  WHERE los_days = 7.0
)
SELECT
  g.discharge_group,
  sp.p50 AS p50_los_days,
  sp.p75 AS p75_los_days,
  sp.p90 AS p90_los_days,
  sp.p95 AS p95_los_days,
  COALESCE(p7.pr_of_7, NULL) AS percentile_rank_of_7_days
FROM (SELECT DISTINCT discharge_group FROM clean) AS g
LEFT JOIN stats_pcts AS sp ON g.discharge_group = sp.discharge_group
LEFT JOIN pr7 AS p7 ON g.discharge_group = p7.discharge_group
WHERE g.discharge_group IN ('HOME','HOSPICE','DEATH')
ORDER BY g.discharge_group;