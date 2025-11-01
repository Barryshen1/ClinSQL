WITH cohort AS (
  -- Female inpatients aged 55-65
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),

asthma_admissions AS (
  -- Admissions with asthma exacerbation diagnosis
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag
  FROM
    cohort c
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON c.hadm_id = d.hadm_id
  WHERE
    (d.icd_version = 9 AND LEFT(d.icd_code, 3) = '493')
    OR (d.icd_version = 10 AND LEFT(d.icd_code, 3) = 'J45')
),

lab_scores AS (
  -- Calculate lab instability score and critical lab rate for each admission
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- LOS in days
    SAFE_DIVIDE(TIMESTAMP_DIFF(a.dischtime, a.admittime, SECOND), 86400) AS los_days,
    -- Lab instability score: abnormal labs in first 48h
    COUNTIF(l.flag = 'abnormal') AS lab_instability_score,
    -- Critical labs in first 48h
    COUNTIF(l.flag = 'critical') AS critical_lab_count,
    -- Total labs in first 48h
    COUNT(l.labevent_id) AS total_lab_count,
    -- Critical lab rate
    SAFE_DIVIDE(COUNTIF(l.flag = 'critical'), COUNT(l.labevent_id)) AS critical_lab_rate
  FROM
    asthma_admissions a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON a.hadm_id = l.hadm_id
      AND l.charttime >= a.admittime
      AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY
    a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

percentile_score AS (
  -- 95th percentile of lab instability score in asthma cohort
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.95) OVER() AS p95_score
  FROM
    lab_scores
),

top_asthma AS (
  -- Top 5% admissions by lab instability score
  SELECT
    l.*,
    p.p95_score
  FROM
    lab_scores l
    CROSS JOIN percentile_score p
  WHERE
    l.lab_instability_score >= p.p95_score
),

-- Repeat for general cohort (not restricted to asthma)
general_lab_scores AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    SAFE_DIVIDE(TIMESTAMP_DIFF(c.dischtime, c.admittime, SECOND), 86400) AS los_days,
    COUNTIF(l.flag = 'abnormal') AS lab_instability_score,
    COUNTIF(l.flag = 'critical') AS critical_lab_count,
    COUNT(l.labevent_id) AS total_lab_count,
    SAFE_DIVIDE(COUNTIF(l.flag = 'critical'), COUNT(l.labevent_id)) AS critical_lab_rate
  FROM
    cohort c
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
      ON c.hadm_id = l.hadm_id
      AND l.charttime >= c.admittime
      AND l.charttime < TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),

general_percentile_score AS (
  SELECT
    PERCENTILE_CONT(lab_instability_score, 0.95) OVER() AS p95_score
  FROM
    general_lab_scores
),

top_general AS (
  SELECT
    l.*,
    p.p95_score
  FROM
    general_lab_scores l
    CROSS JOIN general_percentile_score p
  WHERE
    l.lab_instability_score >= p.p95_score
)

-- Final output: summary stats for top asthma and general cohorts
SELECT
  'Asthma Top 5%' AS cohort,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 4) AS mortality_rate,
  ROUND(AVG(critical_lab_rate), 4) AS avg_critical_lab_rate
FROM
  top_asthma

UNION ALL

SELECT
  'General Top 5%' AS cohort,
  COUNT(*) AS n_admissions,
  ROUND(AVG(los_days), 2) AS avg_los_days,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*), 4) AS mortality_rate,
  ROUND(AVG(critical_lab_rate), 4) AS avg_critical_lab_rate
FROM
  top_general;