WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 83 AND 93
),
group_stats AS (
  SELECT 
    outcome,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
  FROM (
    SELECT 
      TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los,
      CASE 
        WHEN hospital_expire_flag = 1 THEN 'In-hospital death'
        ELSE 'Discharged alive'
      END AS outcome
    FROM cohort
  )
  GROUP BY outcome
),
overall_percentile AS (
  SELECT 
    (COUNTIF(los <= 5) * 100.0) / COUNT(*) AS percentile_rank_5
  FROM (
    SELECT TIMESTAMP_DIFF(dischtime, admittime, DAY) AS los
    FROM cohort
  )
)
SELECT 
  outcome,
  mean_los,
  median_los,
  p75_los,
  p90_los,
  NULL AS percentile_rank_5
FROM group_stats
UNION ALL
SELECT 
  'Overall' AS outcome,
  NULL AS mean_los,
  NULL AS median_los,
  NULL AS p75_los,
  NULL AS p90_los,
  (SELECT percentile_rank_5 FROM overall_percentile) AS percentile_rank_5;