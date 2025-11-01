WITH cohort AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    -- Calculate LOS in days
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, DAY) AS los
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 83 AND 93
    AND adm.admittime IS NOT NULL
    AND adm.dischtime IS NOT NULL
)
, valid_los AS (
  SELECT *
  FROM cohort
  WHERE los >= 0
)
-- Part 1: LOS statistics by discharge status
, los_stats AS (
  SELECT
    hospital_expire_flag,
    COUNT(*) AS n_admissions,
    ROUND(AVG(los), 2) AS mean_los,
    ROUND(APPROX_QUANTILES(los, 100)[OFFSET(50)], 2) AS median_los,
    ROUND(APPROX_QUANTILES(los, 100)[OFFSET(75)], 2) AS p75_los,
    ROUND(APPROX_QUANTILES(los, 100)[OFFSET(90)], 2) AS p90_los
  FROM valid_los
  GROUP BY hospital_expire_flag
)
-- Part 2: Percentile rank of 5-day LOS
, percentile_5day AS (
  SELECT
    ROUND(100.0 * COUNTIF(los <= 5) / COUNT(*), 2) AS percentile_rank_5day
  FROM valid_los
)
SELECT
  'LOS statistics by discharge status' AS section,
  CASE hospital_expire_flag
    WHEN 0 THEN 'Discharged alive'
    WHEN 1 THEN 'In-hospital death'
    ELSE 'Other'
  END AS discharge_status,
  n_admissions,
  mean_los,
  median_los,
  p75_los,
  p90_los,
  NULL AS percentile_rank_5day
FROM los_stats

UNION ALL

SELECT
  'Percentile rank of 5-day LOS' AS section,
  NULL AS discharge_status,
  NULL AS n_admissions,
  NULL AS mean_los,
  NULL AS median_los,
  NULL AS p75_los,
  NULL AS p90_los,
  percentile_rank_5day
FROM percentile_5day
;