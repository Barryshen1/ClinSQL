WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location LIKE 'HOME%' THEN 'Home'
      ELSE 'Facility'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 86 AND 96
    AND a.admission_type = 'URGENT'
    AND a.insurance = 'Medicare'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
    AND a.dischtime >= a.admittime
),

los_stats AS (
  SELECT
    discharge_outcome,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los
  FROM
    filtered_admissions
  GROUP BY
    discharge_outcome
),

percentile_10_day AS (
  SELECT
    discharge_outcome,
    PERCENT_RANK() OVER (PARTITION BY discharge_outcome ORDER BY los_days) AS percentile_rank_10_day
  FROM (
    SELECT
      discharge_outcome,
      los_days,
      ROW_NUMBER() OVER (PARTITION BY discharge_outcome ORDER BY ABS(los_days - 10)) AS rn
    FROM
      filtered_admissions
  ) sub
  WHERE
    rn = 1
)

SELECT
  ls.discharge_outcome,
  ls.mean_los,
  ls.median_los,
  ls.p75_los,
  ls.p90_los,
  p10.percentile_rank_10_day * 100 AS percentile_rank_10_day
FROM
  los_stats ls
LEFT JOIN
  percentile_10_day p10
ON
  ls.discharge_outcome = p10.discharge_outcome
ORDER BY
  ls.discharge_outcome;