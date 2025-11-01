WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.hospital_expire_flag,
    DATE_DIFF(COALESCE(a.deathtime, a.dischtime), a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
    AND a.admission_type = 'transfer from another hospital'
    AND a.admittime IS NOT NULL
    AND (a.dischtime IS NOT NULL OR (a.hospital_expire_flag = 1 AND a.deathtime IS NOT NULL))
),
stratified AS (
  SELECT 
    hospital_expire_flag AS survival_flag,
    COUNT(*) AS num_admissions,
    APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS p50,
    APPROX_QUANTILES(los_days, 100)[OFFSET(75)] AS p75,
    APPROX_QUANTILES(los_days, 100)[OFFSET(90)] AS p90,
    APPROX_QUANTILES(los_days, 100)[OFFSET(95)] AS p95
  FROM cohort
  GROUP BY survival_flag
),
overall_percentile AS (
  SELECT 
    (COUNTIF(los_days <= 10) * 100.0) / NULLIF(COUNT(*), 0) AS percentile_rank_10
  FROM cohort
)
SELECT 
  s.survival_flag,
  s.num_admissions,
  s.p50,
  s.p75,
  s.p90,
  s.p95,
  o.percentile_rank_10
FROM stratified s
CROSS JOIN overall_percentile o
ORDER BY s.survival_flag;