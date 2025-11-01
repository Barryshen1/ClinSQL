WITH base AS (
  SELECT
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'in_hospital_death'
      WHEN LOWER(a.discharge_location) LIKE 'home%' THEN 'home'
      ELSE 'facility'
    END AS discharge_group,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.admission_type IN ('EMERGENCY','URGENT')
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),
base_pos AS (
  SELECT discharge_group, los_days
  FROM base
  WHERE los_days > 0
),
stats AS (
  SELECT
    discharge_group,
    AVG(los_days) AS mean_los_days,
    APPROX_QUANTILES(los_days, 4) AS quantiles
  FROM base_pos
  GROUP BY discharge_group
),
p25_50_75 AS (
  SELECT
    discharge_group,
    mean_los_days,
    quantiles[OFFSET(1)] AS p25,
    quantiles[OFFSET(2)] AS p50,
    quantiles[OFFSET(3)] AS p75
  FROM stats
),
seven AS (
  SELECT
    bp.discharge_group,
    COUNT(*) AS total_n,
    SUM(CASE WHEN bp.los_days < 7 THEN 1 ELSE 0 END) AS less_than_7,
    SUM(CASE WHEN bp.los_days = 7 THEN 1 ELSE 0 END) AS equal_to_7
  FROM base_pos bp
  GROUP BY bp.discharge_group
),
pr7 AS (
  SELECT
    s.discharge_group,
    (s.less_than_7 + 0.5 * s.equal_to_7) / s.total_n AS pr7_of_7_days
  FROM seven s
)
SELECT
  t.discharge_group AS discharge_outcome,
  t.mean_los_days,
  t.p25,
  t.p50,
  t.p75,
  pr7.pr7_of_7_days
FROM p25_50_75 t
LEFT JOIN pr7 pr7
  ON t.discharge_group = pr7.discharge_group
ORDER BY discharge_outcome;