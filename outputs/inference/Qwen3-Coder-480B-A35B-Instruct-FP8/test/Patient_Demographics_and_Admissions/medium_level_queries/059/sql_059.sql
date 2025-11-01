WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 75 AND 85
    AND a.admission_type = 'TRANSFER FROM HOSPITAL'
    AND a.admittime < a.dischtime
),

discharge_groups AS (
  SELECT
    CASE
      WHEN discharge_location = 'HOME' THEN 'HOME'
      WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
      WHEN hospital_expire_flag = 1 THEN 'IN_HOSPITAL_DEATH'
      ELSE 'OTHER'
    END AS discharge_group,
    los_days
  FROM
    cohort
  WHERE
    los_days IS NOT NULL
),

grouped_stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS total_patients,
    COUNTIF(los_days >= 7) AS los_ge_7,
    COUNTIF(los_days >= 7) * 1.0 / COUNT(*) AS proportion_ge_7
  FROM
    discharge_groups
  WHERE
    discharge_group IN ('HOME', 'HOSPICE', 'IN_HOSPITAL_DEATH')
  GROUP BY
    discharge_group
),

percentile_7 AS (
  SELECT
    APPROX_QUANTILES(los_days, 100)[OFFSET(7)] AS los_7_percentile
  FROM
    discharge_groups
  WHERE
    discharge_group IN ('HOME', 'HOSPICE', 'IN_HOSPITAL_DEATH')
)

SELECT
  g.discharge_group,
  g.total_patients,
  g.los_ge_7,
  g.proportion_ge_7,
  p.los_7_percentile
FROM
  grouped_stats g
CROSS JOIN
  percentile_7 p
ORDER BY
  g.discharge_group;