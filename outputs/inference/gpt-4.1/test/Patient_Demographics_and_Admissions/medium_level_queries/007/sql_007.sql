WITH cohort AS (
  SELECT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    a.admission_location,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND (
      LOWER(a.admission_location) LIKE '%transfer%'
      OR LOWER(a.admission_location) LIKE '%other hospital%'
    )
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS los_p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS los_p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS los_p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS los_p95
  FROM
    cohort
  GROUP BY
    hospital_expire_flag
)
, percentiles AS (
  SELECT
    hospital_expire_flag,
    -- Percentile rank of 10-day LOS among this group
    PERCENT_RANK() OVER (
      PARTITION BY hospital_expire_flag
      ORDER BY los_days
    ) AS percentile_rank_10d,
    los_days
  FROM
    cohort
  WHERE
    los_days = 10
)
-- Final output: join stats and percentile rank for 10-day LOS
SELECT
  CASE s.hospital_expire_flag
    WHEN 0 THEN 'Survived'
    WHEN 1 THEN 'In-hospital death'
    ELSE 'Unknown'
  END AS outcome,
  s.num_admissions,
  s.los_p50,
  s.los_p75,
  s.los_p90,
  s.los_p95,
  -- If multiple admissions with los_days=10, show average percentile rank
  IFNULL(AVG(p.percentile_rank_10d), NULL) AS percentile_rank_10d
FROM
  stats s
LEFT JOIN
  percentiles p
  ON s.hospital_expire_flag = p.hospital_expire_flag
GROUP BY
  s.hospital_expire_flag, s.num_admissions, s.los_p50, s.los_p75, s.los_p90, s.los_p95
ORDER BY
  s.hospital_expire_flag;