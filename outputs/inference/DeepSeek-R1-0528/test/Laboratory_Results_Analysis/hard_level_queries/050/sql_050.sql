WITH base_cohort AS (
  SELECT 
    p.subject_id, 
    p.gender, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 40 AND 50
),

ards_cohort AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code = '51882') OR  -- ICD-9: 518.82
    (icd_version = 10 AND icd_code = 'J80')      -- ICD-10: J80
),

lab_events AS (
  SELECT 
    l.hadm_id,
    l.flag,
    CASE 
      WHEN l.flag = 'abnormal' THEN 1
      WHEN l.flag = 'critically abnormal' THEN 2
      ELSE 0 
    END AS instability_points,
    CASE 
      WHEN l.flag = 'critically abnormal' THEN 1 
      ELSE 0 
    END AS critical_event
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN base_cohort b 
    ON l.hadm_id = b.hadm_id
  WHERE 
    l.charttime BETWEEN b.admittime AND DATETIME_ADD(b.admittime, INTERVAL 72 HOUR)
),

lab_summary AS (
  SELECT 
    hadm_id,
    COALESCE(SUM(instability_points), 0) AS instability_score,
    COALESCE(SUM(critical_event), 0) AS critical_lab_events
  FROM lab_events
  GROUP BY hadm_id
),

ards_with_lab AS (
  SELECT 
    b.*, 
    l.instability_score,
    l.critical_lab_events
  FROM base_cohort b
  INNER JOIN ards_cohort a 
    ON b.hadm_id = a.hadm_id
  LEFT JOIN lab_summary l 
    ON b.hadm_id = l.hadm_id
),

percentile_75 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS p75
  FROM ards_with_lab
),

ards_high_risk AS (
  SELECT 
    a.*
  FROM ards_with_lab a
  CROSS JOIN percentile_75 p
  WHERE a.instability_score >= p.p75
),

non_ards_with_lab AS (
  SELECT 
    b.*, 
    COALESCE(l.critical_lab_events, 0) AS critical_lab_events
  FROM base_cohort b
  LEFT JOIN lab_summary l 
    ON b.hadm_id = l.hadm_id
  WHERE NOT EXISTS (
    SELECT 1 
    FROM ards_cohort a 
    WHERE a.hadm_id = b.hadm_id
  )
)

SELECT 
  (SELECT p75 FROM percentile_75) AS instability_score_75th_percentile,
  (SELECT AVG(hospital_expire_flag) FROM ards_high_risk) AS mortality_rate,
  (SELECT AVG(DATETIME_DIFF(dischtime, admittime, DAY)) FROM ards_high_risk) AS mean_los_days,
  (SELECT AVG(critical_lab_events) FROM ards_high_risk) AS avg_critical_events_ards_high,
  (SELECT AVG(critical_lab_events) FROM non_ards_with_lab) AS avg_critical_events_control
FROM ards_high_risk
LIMIT 1;