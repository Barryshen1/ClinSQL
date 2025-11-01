WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-Hospital Death'
      WHEN a.discharge_location = 'HOME' THEN 'Discharged Home'
      WHEN a.discharge_location = 'HOSPICE' THEN 'Hospice'
      ELSE 'Other'
    END AS discharge_group
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 57 AND 67
    AND a.edregtime IS NOT NULL
    AND a.edouttime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),
grouped_stats AS (
  SELECT
    discharge_group,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90_los,
    -- Percentile rank of 10 days: fraction of stays <= 10 days
    COUNTIF(los_days <= 10) * 100.0 / COUNT(*) AS percentile_rank_10_days
  FROM
    cohort
  WHERE
    discharge_group IN ('Discharged Home', 'Hospice', 'In-Hospital Death')
  GROUP BY
    discharge_group
)
SELECT
  discharge_group,
  ROUND(mean_los, 2) AS mean_los,
  ROUND(median_los, 2) AS median_los,
  ROUND(p75_los, 2) AS p75_los,
  ROUND(p90_los, 2) AS p90_los,
  ROUND(percentile_rank_10_days, 2) AS percentile_rank_10_days
FROM
  grouped_stats
ORDER BY
  discharge_group;