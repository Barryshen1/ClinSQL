WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    p.anchor_age,
    p.gender,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN UPPER(discharge_location) LIKE '%HOME%' THEN 'Home'
      WHEN UPPER(discharge_location) LIKE '%SKILLED NURSING%' THEN 'SNF/rehab/LTACH'
      WHEN UPPER(discharge_location) LIKE '%REHAB%' THEN 'SNF/rehab/LTACH'
      WHEN UPPER(discharge_location) LIKE '%LTAC%' THEN 'SNF/rehab/LTACH'
      WHEN UPPER(discharge_location) LIKE '%LONG TERM ACUTE%' THEN 'SNF/rehab/LTACH'
      ELSE NULL
    END AS discharge_group
  FROM cohort
)

, los_percentile AS (
  SELECT DISTINCT
    discharge_group,
    PERCENTILE_CONT(los_days, 0.14) OVER (PARTITION BY discharge_group) AS los_14th_percentile
  FROM discharge_groups
  WHERE discharge_group IS NOT NULL
)

, agg AS (
  SELECT
    discharge_group,
    COUNT(*) AS n_admissions,
    SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS n_LOS_ge_7,
    SAFE_DIVIDE(SUM(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END), COUNT(*)) AS proportion_LOS_ge_7
  FROM discharge_groups
  WHERE discharge_group IS NOT NULL
  GROUP BY discharge_group
)

SELECT
  agg.discharge_group,
  agg.n_admissions,
  agg.n_LOS_ge_7,
  agg.proportion_LOS_ge_7,
  los_percentile.los_14th_percentile
FROM agg
LEFT JOIN los_percentile
  ON agg.discharge_group = los_percentile.discharge_group
ORDER BY agg.discharge_group;