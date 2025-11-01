WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),

labs_72h AS (
  SELECT 
    c.hadm_id,
    COUNT(l.labevent_id) AS abnormal_lab_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
    AND l.charttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
    AND l.flag IS NOT NULL  -- considering flagged values as abnormal
  GROUP BY c.hadm_id
),

cohort_with_labs AS (
  SELECT 
    c.*,
    COALESCE(l.abnormal_lab_count, 0) AS abnormal_lab_count
  FROM cohort c
  LEFT JOIN labs_72h l
    ON c.hadm_id = l.hadm_id
),

p95 AS (
  SELECT 
    APPROX_QUANTILES(abnormal_lab_count, 100)[OFFSET(95)] AS p95_value
  FROM cohort_with_labs
)

SELECT 
  'High Risk (>=P95)' AS group_label,
  COUNT(*) AS num_patients,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(abnormal_lab_count) AS avg_critical_lab_events
FROM cohort_with_labs
WHERE abnormal_lab_count >= (SELECT p95_value FROM p95)

UNION ALL

SELECT 
  'All Cohort' AS group_label,
  COUNT(*) AS num_patients,
  AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS mean_los_days,
  AVG(hospital_expire_flag) AS in_hospital_mortality_rate,
  AVG(abnormal_lab_count) AS avg_critical_lab_events
FROM cohort_with_labs;