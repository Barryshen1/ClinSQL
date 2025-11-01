WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
),

discharge_groups AS (
  SELECT
    *,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location = 'HOME' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM
    cohort
),

los_stats AS (
  SELECT
    discharge_category,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY discharge_category ORDER BY los_days) AS los_percentile_rank
  FROM
    discharge_groups
),

summary AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_patients,
    AVG(CASE WHEN los_days >= 7 THEN 1 ELSE 0 END) AS prop_los_ge_7,
    MAX(CASE WHEN los_days = 10 THEN los_percentile_rank END) AS percentile_rank_10_days
  FROM
    los_stats
  GROUP BY
    discharge_category
)

SELECT
  discharge_category,
  prop_los_ge_7,
  percentile_rank_10_days
FROM
  summary
ORDER BY
  discharge_category;