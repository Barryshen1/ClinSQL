WITH filtered_admissions AS (
  SELECT
    CASE 
      WHEN a.hospital_expire_flag = 0 THEN 'Survived'
      ELSE 'Died'
    END AS outcome,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND LOWER(a.admission_location) LIKE 'transfer%'
)
SELECT
  outcome,
  COUNT(*) AS admissions,
  -- Approximate percentiles from LOS distribution
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95_los,
  -- Percentile rank of a 10-day LOS
  ROUND(
    100.0 * SUM(CASE WHEN los <= 10 THEN 1 ELSE 0 END) / COUNT(*)
  , 2) AS pct_rank_10day
FROM filtered_admissions
GROUP BY outcome
ORDER BY outcome;