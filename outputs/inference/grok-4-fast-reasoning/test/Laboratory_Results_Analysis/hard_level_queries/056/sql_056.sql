WITH asthma_diag AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND (icd_code LIKE 'J45%' OR icd_code LIKE 'J46%'))
     OR (icd_version = 9 AND icd_code LIKE '493%')
),
general_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 55
    AND p.anchor_age <= 65
),
asthma_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN asthma_diag ad ON a.hadm_id = ad.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 55
    AND p.anchor_age <= 65
),
labs_general AS (
  SELECT 
    le.hadm_id,
    COUNTIF(le.valuenum IS NOT NULL) AS total_labs,
    COUNTIF(le.valuenum IS NOT NULL AND le.flag <> '') AS abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN general_cohort c ON le.hadm_id = c.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY le.hadm_id
),
labs_asthma AS (
  SELECT 
    le.hadm_id,
    COUNTIF(le.valuenum IS NOT NULL) AS total_labs,
    COUNTIF(le.valuenum IS NOT NULL AND le.flag <> '') AS abnormal_labs
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN asthma_cohort c ON le.hadm_id = c.hadm_id
  WHERE le.charttime >= c.admittime
    AND le.charttime < DATETIME_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY le.hadm_id
),
general_scores AS (
  SELECT 
    c.hadm_id, 
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag,
    COALESCE(l.total_labs, 0) AS total_labs,
    COALESCE(l.abnormal_labs, 0) AS score
  FROM general_cohort c
  LEFT JOIN labs_general l USING (hadm_id)
),
asthma_scores AS (
  SELECT 
    c.hadm_id, 
    DATETIME_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days,
    c.hospital_expire_flag,
    COALESCE(l.total_labs, 0) AS total_labs,
    COALESCE(l.abnormal_labs, 0) AS score
  FROM asthma_cohort c
  LEFT JOIN labs_asthma l USING (hadm_id)
),
p95_cte AS (
  SELECT APPROX_QUANTILES(score, 100)[OFFSET(95)] AS p95_score
  FROM asthma_scores
),
general_stats AS (
  SELECT 
    AVG(los_days) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    IFNULL(SUM(score) / NULLIF(SUM(total_labs), 0), 0) AS critical_lab_rate
  FROM general_scores
),
top_stats AS (
  SELECT 
    AVG(los_days) AS avg_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
    IFNULL(SUM(score) / NULLIF(SUM(total_labs), 0), 0) AS critical_lab_rate
  FROM asthma_scores
  WHERE score >= (SELECT p95_score FROM p95_cte)
)
SELECT 
  (SELECT p95_score FROM p95_cte) AS percentile_95,
  g.avg_los AS general_los_days,
  g.mortality_rate AS general_mortality_rate,
  g.critical_lab_rate AS general_critical_lab_rate,
  t.avg_los AS top_tier_los_days,
  t.mortality_rate AS top_tier_mortality_rate,
  t.critical_lab_rate AS top_tier_critical_lab_rate
FROM general_stats g, top_stats t;