WITH base AS (
  SELECT
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND) / 86400.0 AS LOS_days,
    LOWER(a.discharge_location) AS dis_location,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE NOT LOWER(a.admission_type) LIKE '%emergency%'
    AND p.gender = 'Male'
    AND p.anchor_age BETWEEN 80 AND 90
    AND a.dischtime IS NOT NULL
),
stats AS (
  SELECT
    AVG(LOS_days) AS mean_los_days,
    APPROX_QUANTILES(LOS_days, 100) AS quantiles
  FROM base
),
quant AS (
  SELECT
    quantiles[OFFSET(24)] AS p25_days,   -- approx 25th percentile
    quantiles[OFFSET(49)] AS median_days,-- approx 50th percentile
    quantiles[OFFSET(74)] AS p75_days,   -- approx 75th percentile
    quantiles[OFFSET(90)] AS p90_days
  FROM stats
),
perc AS (
  SELECT
    SUM(CASE WHEN dis_location = 'home' AND LOS_days <= 14 THEN 1 ELSE 0 END) /
      NULLIF(SUM(CASE WHEN dis_location = 'home' THEN 1 ELSE 0 END), 0) AS pct_home_le14,
    SUM(CASE WHEN dis_location = 'hospice' AND LOS_days <= 14 THEN 1 ELSE 0 END) /
      NULLIF(SUM(CASE WHEN dis_location = 'hospice' THEN 1 ELSE 0 END), 0) AS pct_hospice_le14,
    SUM(CASE WHEN hospital_expire_flag = 1 AND LOS_days <= 14 THEN 1 ELSE 0 END) /
      NULLIF(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END), 0) AS pct_death_le14
  FROM base
)
SELECT
  s.mean_los_days,
  q.p25_days AS p25_days,
  q.median_days AS median_days,
  q.p75_days AS p75_days,
  q.p90_days AS p90_days,
  p.pct_home_le14,
  p.pct_hospice_le14,
  p.pct_death_le14
FROM stats s, quant q, perc p;