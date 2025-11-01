WITH male_ed_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.discharge_location,
    a.hospital_expire_flag,
    p.anchor_age,
    TIMESTAMP_DIFF(
      COALESCE(a.deathtime, a.dischtime),
      a.admittime,
      DAY
    ) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND a.admission_location = 'EMERGENCY ROOM ADMIT'
    AND a.discharge_location IS NOT NULL
),

discharge_categories AS (
  SELECT
    hadm_id,
    los_days,
    CASE
      WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN discharge_location LIKE '%HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_category
  FROM
    male_ed_admissions
),

stats_with_ranks AS (
  SELECT
    discharge_category,
    los_days,
    PERCENT_RANK() OVER (
      PARTITION BY discharge_category
      ORDER BY los_days
    ) AS percentile_rank,
    CASE WHEN los_days >= 7 THEN 1 ELSE 0 END AS los_ge7
  FROM
    discharge_categories
),

stats_by_category AS (
  SELECT
    discharge_category,
    COUNT(*) AS total_admissions,
    SUM(los_ge7) AS los_ge7_count,
    AVG(CASE WHEN los_days = 10 THEN percentile_rank ELSE NULL END) AS percentile_rank_10day
  FROM
    stats_with_ranks
  GROUP BY
    discharge_category
)

SELECT
  discharge_category,
  ROUND(los_ge7_count / total_admissions, 4) AS proportion_los_ge7,
  ROUND(percentile_rank_10day, 4) AS avg_percentile_rank_10day
FROM
  stats_by_category
ORDER BY
  discharge_category;