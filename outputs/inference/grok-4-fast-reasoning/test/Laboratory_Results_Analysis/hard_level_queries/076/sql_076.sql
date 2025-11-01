WITH elderly_cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),
elderly_scores AS (
  SELECT 
    c.hadm_id, 
    c.admittime, 
    c.dischtime, 
    c.hospital_expire_flag,
    COUNT(CASE WHEN l.flag != '' THEN 1 END) AS instability_score
  FROM elderly_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime <= c.admittime + INTERVAL 72 HOUR
  GROUP BY c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
p95_calc AS (
  SELECT PERCENTILE_CONT(instability_score, 0.95) AS p95
  FROM elderly_scores
),
high_scores AS (
  SELECT 
    s.hadm_id, 
    s.admittime, 
    s.dischtime, 
    s.hospital_expire_flag,
    s.instability_score
  FROM elderly_scores s
  CROSS JOIN p95_calc p
  WHERE s.instability_score >= p.p95
),
all_cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
all_scores AS (
  SELECT 
    c.hadm_id, 
    COUNT(CASE WHEN l.flag != '' THEN 1 END) AS instability_score
  FROM all_cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON c.hadm_id = l.hadm_id
    AND l.charttime >= c.admittime
    AND l.charttime <= c.admittime + INTERVAL 72 HOUR
  GROUP BY c.hadm_id
),
general_avg AS (
  SELECT AVG(instability_score) AS general_avg_critical
  FROM all_scores
),
high_los AS (
  SELECT AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days
  FROM high_scores
),
high_mortality AS (
  SELECT AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100 AS mortality_pct
  FROM high_scores
),
high_avg_events AS (
  SELECT AVG(instability_score) AS high_avg_critical
  FROM high_scores
)
SELECT '95th percentile of 72-hour lab instability score' AS metric, CAST(p95 AS FLOAT64) AS value
FROM p95_calc
UNION ALL
SELECT 'Mean LOS for patients >= P95 (days)' AS metric, mean_los_days AS value
FROM high_los
UNION ALL
SELECT 'In-hospital mortality for patients >= P95 (%)' AS metric, mortality_pct AS value
FROM high_mortality
UNION ALL
SELECT 'Avg critical lab events per patient for >= P95' AS metric, high_avg_critical AS value
FROM high_avg_events
UNION ALL
SELECT 'Avg critical lab events per patient for general inpatients' AS metric, general_avg_critical AS value
FROM general_avg;