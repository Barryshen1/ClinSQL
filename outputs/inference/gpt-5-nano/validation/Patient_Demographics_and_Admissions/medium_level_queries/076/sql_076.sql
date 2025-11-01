WITH base AS (
  SELECT
    CASE WHEN a.hospital_expire_flag = 1 THEN 'DEATH' ELSE 'ALIVE' END AS status,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  WHERE a.dischtime IS NOT NULL
    AND p.anchor_age BETWEEN 83 AND 93
    AND p.gender = 'M'
),
valid AS (
  SELECT status, los_days
  FROM base
  WHERE los_days >= 0
),
stats AS (
  SELECT
    status,
    AVG(los_days) AS mean_los
  FROM valid
  GROUP BY status
),
quant AS (
  SELECT
    status,
    APPROX_QUANTILES(los_days, 100) AS qq
  FROM valid
  GROUP BY status
),
quantified AS (
  SELECT
    s.status,
    s.mean_los,
    q.qq[OFFSET(50)] AS p50,
    q.qq[OFFSET(75)] AS p75,
    q.qq[OFFSET(90)] AS p90
  FROM stats s
  JOIN quant q ON q.status = s.status
),
tmp AS (
  SELECT status, los_days, FALSE AS is_synth
  FROM valid
  UNION ALL
  SELECT status, 5.0 AS los_days, TRUE AS is_synth
  FROM (SELECT DISTINCT status FROM valid)
),
ranked AS (
  SELECT
    status,
    los_days,
    is_synth,
    PERCENT_RANK() OVER (PARTITION BY status ORDER BY los_days) AS pr
  FROM tmp
),
rank_result AS (
  SELECT
    status,
    MAX(CASE WHEN is_synth THEN pr END) AS pr5
  FROM ranked
  GROUP BY status
)
SELECT
  quantified.status,
  quantified.mean_los,
  quantified.p50,
  quantified.p75,
  quantified.p90,
  ROUND(rank_result.pr5 * 100, 2) AS percentile_rank_of_5day
FROM quantified
JOIN rank_result USING (status)
ORDER BY quantified.status;