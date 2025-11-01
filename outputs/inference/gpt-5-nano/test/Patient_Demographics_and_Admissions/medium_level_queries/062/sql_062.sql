WITH base AS (
  SELECT
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days,
    p.gender,
    p.anchor_age,
    -- Discharge grouping
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 'Home'
      WHEN LOWER(a.discharge_location) LIKE '%snf%' 
           OR LOWER(a.discharge_location) LIKE '%rehab%' 
           OR LOWER(a.discharge_location) LIKE '%ltach%' THEN 'SNF/Rehab/LTACH'
      ELSE 'Other'
    END AS discharge_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age >= 64 AND p.anchor_age <= 74
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
filtered AS (
  SELECT discharge_group, los_days
  FROM base
  WHERE discharge_group IN ('Home','SNF/Rehab/LTACH','In-hospital death')
),
grouped AS (
  SELECT
    discharge_group,
    COUNT(*) AS total,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS count_ge7,
    SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS proportion_ge7
  FROM filtered
  GROUP BY discharge_group
),
percentile_vals AS (
  SELECT APPROX_QUANTILES(los_days, 100) AS quantiles
  FROM base
),
percentile_p14 AS (
  SELECT quantiles[OFFSET(13)] AS p14
  FROM percentile_vals
)

SELECT
  g.discharge_group,
  g.total,
  g.count_ge7,
  g.proportion_ge7,
  p14 AS p14
FROM grouped g
CROSS JOIN percentile_p14 p14
ORDER BY g.discharge_group;