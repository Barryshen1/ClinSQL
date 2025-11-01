WITH transfer_in_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    TIMESTAMP_DIFF(
      COALESCE(TIMESTAMP(a.dischtime), CURRENT_TIMESTAMP()),
      TIMESTAMP(a.admittime),
      DAY
    ) AS los_days,
    CASE
      WHEN a.discharge_location LIKE '%HOME%' THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/Rehab/LTACH'
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital Mortality'
      ELSE 'Other'
    END AS discharge_category
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type = 'TRANSFER'
    AND a.hadm_id IS NOT NULL
),

stats_by_category AS (
  SELECT
    discharge_category,
    COUNT(*) AS n,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95
  FROM
    transfer_in_patients
  GROUP BY
    discharge_category
),

percentile_ranks AS (
  SELECT
    discharge_category,
    los_days,
    PERCENT_RANK() OVER (PARTITION BY discharge_category ORDER BY los_days) AS percentile_rank
  FROM
    transfer_in_patients
)

SELECT
  s.discharge_category,
  s.n,
  ROUND(s.mean_los, 2) AS mean_los,
  ROUND(s.p25, 2) AS p25,
  ROUND(s.median, 2) AS median,
  ROUND(s.p75, 2) AS p75,
  ROUND(s.p90, 2) AS p90,
  ROUND(s.p95, 2) AS p95,
  ROUND(p.percentile_rank * 100, 2) AS percentile_rank_5day
FROM
  stats_by_category s
CROSS JOIN
  (SELECT DISTINCT discharge_category, percentile_rank
   FROM percentile_ranks
   WHERE los_days = 5) p
WHERE
  s.discharge_category = p.discharge_category
ORDER BY
  s.discharge_category;