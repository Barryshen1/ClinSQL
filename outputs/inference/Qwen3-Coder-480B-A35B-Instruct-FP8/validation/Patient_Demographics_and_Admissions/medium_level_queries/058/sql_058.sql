WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.discharge_location,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'In-hospital mortality'
      WHEN a.discharge_location = 'HOME' THEN 'Home'
      WHEN a.discharge_location IN ('SNF', 'REHAB', 'LTACH') THEN 'SNF/rehab/LTACH'
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
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type = 'TRANSFER'
    AND a.admission_location != 'EMERGENCY ROOM'
    AND a.dischtime IS NOT NULL
    AND a.admittime IS NOT NULL
),

stats AS (
  SELECT
    discharge_group,
    COUNT(*) AS n,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los, 100)[OFFSET(95)] AS p95,
    -- Percentile rank of 5-day stay
    SAFE_DIVIDE(COUNTIF(los < 5), COUNT(*)) AS percentile_rank_5_days
  FROM
    cohort
  GROUP BY
    discharge_group
)

SELECT
  discharge_group,
  n,
  ROUND(mean_los, 2) AS mean_los,
  p25,
  median,
  p75,
  p90,
  p95,
  ROUND(percentile_rank_5_days * 100, 2) AS percentile_rank_5_days
FROM
  stats
ORDER BY
  discharge_group;