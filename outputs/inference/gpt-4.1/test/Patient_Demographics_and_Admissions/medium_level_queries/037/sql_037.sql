WITH filtered_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400) AS los_days
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type != 'EMERGENCY'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
)
, valid_admissions AS (
  SELECT *
  FROM filtered_admissions
  WHERE los_days >= 0
)
, percentiles AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS n_admissions,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95
  FROM valid_admissions
  GROUP BY hospital_expire_flag
)
, percentile_rank_7d AS (
  SELECT
    hospital_expire_flag,
    -- Find percentile rank for LOS closest to 7 days in each group
    ARRAY_AGG(
      STRUCT(
        los_days,
        percentile_rank
      )
      ORDER BY ABS(los_days - 7)
      LIMIT 1
    )[OFFSET(0)] AS closest_los
  FROM (
    SELECT
      hospital_expire_flag,
      los_days,
      PERCENT_RANK() OVER (PARTITION BY hospital_expire_flag ORDER BY los_days) AS percentile_rank
    FROM valid_admissions
  )
  GROUP BY hospital_expire_flag
)
SELECT
  CASE p.hospital_expire_flag
    WHEN 0 THEN 'Discharged Alive'
    WHEN 1 THEN 'In-Hospital Death'
    ELSE 'Unknown'
  END AS outcome,
  p.n_admissions,
  p.p50,
  p.p75,
  p.p90,
  p.p95,
  pr.closest_los.los_days AS los_closest_to_7d,
  pr.closest_los.percentile_rank AS percentile_rank_of_7d
FROM percentiles p
LEFT JOIN percentile_rank_7d pr
  ON p.hospital_expire_flag = pr.hospital_expire_flag
ORDER BY p.hospital_expire_flag;