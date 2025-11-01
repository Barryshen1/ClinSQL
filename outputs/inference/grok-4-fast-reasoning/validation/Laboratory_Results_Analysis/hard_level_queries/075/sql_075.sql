WITH cohort_hadm AS (
  SELECT DISTINCT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 42 AND 52
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '453.4%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I82.4%' OR d.icd_code LIKE 'I82.5%'))
        )
    )
),
scores AS (
  SELECT 
    c.*,
    COUNT(le.labevent_id) AS instability_score
  FROM cohort_hadm c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY 
    c.subject_id, c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag
),
p95 AS (
  SELECT 
    PERCENTILE_CONT(instability_score, 0.95) OVER () AS p95_score
  FROM scores
  LIMIT 1
),
high_risk AS (
  SELECT s.*
  FROM scores s
  CROSS JOIN p95
  WHERE s.instability_score >= p95.p95_score
),
all_inpatients_scores AS (
  SELECT 
    COUNT(le.labevent_id) AS instability_score_all
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON a.hadm_id = le.hadm_id
    AND le.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND le.flag = 'abnormal'
  GROUP BY a.hadm_id
),
avg_score_all AS (
  SELECT AVG(instability_score_all) AS mean_critical_rate_all
  FROM all_inpatients_scores
),
high_metrics AS (
  SELECT 
    (SELECT p95_score FROM p95) AS percentile_95,
    AVG(CAST(hospital_expire_flag AS FLOAT)) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
    AVG(instability_score) AS mean_critical_rate_high
  FROM high_risk
)
SELECT 
  percentile_95,
  mortality_rate,
  mean_los_days,
  mean_critical_rate_high AS critical_lab_rate_high_risk,
  mean_critical_rate_all AS critical_lab_rate_all_inpatients
FROM high_metrics
CROSS JOIN avg_score_all;