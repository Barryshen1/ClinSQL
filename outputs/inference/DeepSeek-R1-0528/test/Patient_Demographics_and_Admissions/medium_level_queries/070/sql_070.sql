WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los,
    CASE
      WHEN a.hospital_expire_flag = 1 THEN 'Death'
      WHEN a.discharge_location LIKE 'HOSPICE%' THEN 'Hospice'
      WHEN a.discharge_location = 'HOME' AND a.hospital_expire_flag = 0 THEN 'Home'
    END AS disposition_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE
    a.admission_type = 'EMERGENCY'
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 57 AND 67
    AND ( 
      a.hospital_expire_flag = 1
      OR a.discharge_location LIKE 'HOSPICE%'
      OR (a.discharge_location = 'HOME' AND a.hospital_expire_flag = 0)
    )
),
grouped_stats AS (
  SELECT
    disposition_group,
    AVG(los) AS mean_los,
    APPROX_QUANTILES(los, 100)[OFFSET(50)] AS median_los,
    APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
    APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los
  FROM cohort
  GROUP BY disposition_group
),
overall_percentile AS (
  SELECT
    SAFE_DIVIDE(COUNTIF(los <= 10) * 100.0, COUNT(*)) AS percentile_rank_10
  FROM cohort
)
SELECT
  disposition_group,
  mean_los,
  median_los,
  p75_los,
  p90_los,
  NULL AS percentile_rank_10
FROM grouped_stats
UNION ALL
SELECT
  'Overall' AS disposition_group,
  NULL AS mean_los,
  NULL AS median_los,
  NULL AS p75_los,
  NULL AS p90_los,
  percentile_rank_10
FROM overall_percentile;