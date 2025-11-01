WITH patients_55_65 AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
),
lab_events AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    COUNT(CASE WHEN l.flag IS NOT NULL THEN 1 END) AS total_abnormal,
    COUNT(*) AS total_labs,
    COUNT(CASE WHEN l.flag IN ('H', 'L') THEN 1 END) AS critical_labs
  FROM patients_55_65 p
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON p.hadm_id = l.hadm_id
    AND l.charttime BETWEEN p.admittime AND p.admittime + INTERVAL 48 HOUR
  GROUP BY p.subject_id, p.hadm_id
),
percentile_95 AS (
  SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY total_abnormal) AS percentile_95
  FROM lab_events
),
top_tier AS (
  SELECT 
    l.subject_id,
    l.hadm_id,
    l.total_abnormal,
    l.total_labs,
    l.critical_labs,
    p.percentile_95,
    CASE WHEN l.total_abnormal >= p.percentile_95 THEN 1 ELSE 0 END AS is_top_tier
  FROM lab_events l
  CROSS JOIN percentile_95 p
)
SELECT 
  is_top_tier,
  AVG(DATE_DIFF(dischtime, admittime, DAY)) AS avg_los,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(SAFE_DIVIDE(critical_labs, total_labs)) AS critical_lab_rate
FROM top_tier t
JOIN patients_55_65 p 
  ON t.subject_id = p.subject_id AND t.hadm_id = p.hadm_id
GROUP BY is_top_tier;