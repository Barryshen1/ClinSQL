WITH female_urgent_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24 AS los_days,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital death'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location LIKE '%FACILITY%' THEN 'Facility'
      ELSE 'Other'
    END AS discharge_outcome
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type IN ('URGENT', 'EMERGENCY')
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) > 0
),

los_stats AS (
  SELECT
    discharge_outcome,
    AVG(los_days) AS mean_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(25)] AS p25_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50_los,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75_los
  FROM
    female_urgent_admissions
  GROUP BY
    discharge_outcome
),

percentile_rank_7day AS (
  SELECT
    discharge_outcome,
    PERCENT_RANK() OVER (PARTITION BY discharge_outcome ORDER BY los_days) AS percentile_rank
  FROM
    female_urgent_admissions
  WHERE
    los_days = 7
)

SELECT
  ls.discharge_outcome,
  ROUND(ls.mean_los, 2) AS mean_los_days,
  ROUND(ls.p25_los, 2) AS p25_los_days,
  ROUND(ls.p50_los, 2) AS p50_los_days,
  ROUND(ls.p75_los, 2) AS p75_los_days,
  ROUND(pr.percentile_rank * 100, 2) AS percentile_rank_7day
FROM
  los_stats ls
LEFT JOIN
  percentile_rank_7day pr
ON
  ls.discharge_outcome = pr.discharge_outcome
ORDER BY
  ls.discharge_outcome;