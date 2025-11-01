WITH cohort AS (
  SELECT
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type != 'EMERGENCY'
    AND p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 52 AND 62
)

-- Part 1: Percentiles by discharge status
SELECT
  'percentile' AS type,
  hospital_expire_flag,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
  COUNT(*) AS num_admissions,
  NULL AS percentile_rank_7
FROM cohort
GROUP BY hospital_expire_flag

UNION ALL

-- Part 2: Percentile rank of 7 days (entire cohort)
SELECT
  'percentile_rank' AS type,
  NULL AS hospital_expire_flag,
  NULL AS p50,
  NULL AS p75,
  NULL AS p90,
  NULL AS p95,
  COUNT(*) AS num_admissions,
  (COUNTIF(los <= 7) * 100.0) / COUNT(*) AS percentile_rank_7
FROM cohort;