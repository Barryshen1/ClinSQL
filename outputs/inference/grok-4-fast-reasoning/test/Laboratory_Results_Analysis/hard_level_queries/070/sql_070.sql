WITH eligible_admissions AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age >= 40 
    AND p.anchor_age <= 50
),
stroke_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND (icd_code LIKE 'I60%' OR icd_code LIKE 'I61%' OR icd_code LIKE 'I62%'))
     OR (icd_version = 9 AND (icd_code LIKE '430%' OR icd_code LIKE '431%' OR icd_code LIKE '432%'))
),
lab_summary AS (
  SELECT 
    le.hadm_id,
    COUNT(CASE WHEN le.flag = 'abnormal' THEN 1 END) AS abnormal_events,
    COUNT(*) AS total_events,
    COUNT(DISTINCT CASE WHEN le.flag = 'abnormal' THEN le.itemid END) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN eligible_admissions ea 
    ON le.subject_id = ea.subject_id AND le.hadm_id = ea.hadm_id
  WHERE le.charttime >= ea.admittime
    AND le.charttime < TIMESTAMP_ADD(ea.admittime, INTERVAL 72 HOUR)
  GROUP BY le.hadm_id
),
stroke_data AS (
  SELECT 
    ea.*,
    COALESCE(ls.instability_score, 0) AS instability_score,
    COALESCE(ls.abnormal_events, 0) AS abnormal_events,
    COALESCE(ls.total_events, 0) AS total_events
  FROM eligible_admissions ea
  JOIN stroke_hadms sh ON ea.hadm_id = sh.hadm_id
  LEFT JOIN lab_summary ls ON ea.hadm_id = ls.hadm_id
),
stroke_strat AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY instability_score ASC) AS quartile
  FROM stroke_data
),
stroke_summary AS (
  SELECT 
    CONCAT('Q', quartile) AS group_name,
    COUNT(*) AS n,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_pct,
    SAFE_DIVIDE(SUM(abnormal_events), SUM(total_events)) AS abnormal_rate
  FROM stroke_strat
  GROUP BY quartile
),
general_data AS (
  SELECT 
    ea.*,
    COALESCE(ls.instability_score, 0) AS instability_score,
    COALESCE(ls.abnormal_events, 0) AS abnormal_events,
    COALESCE(ls.total_events, 0) AS total_events
  FROM eligible_admissions ea
  LEFT JOIN lab_summary ls ON ea.hadm_id = ls.hadm_id
),
general_summary AS (
  SELECT 
    'General' AS group_name,
    COUNT(*) AS n,
    AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS avg_los_days,
    SUM(hospital_expire_flag) * 100.0 / COUNT(*) AS mortality_pct,
    SAFE_DIVIDE(SUM(abnormal_events), SUM(total_events)) AS abnormal_rate
  FROM general_data
)
SELECT * FROM stroke_summary
UNION ALL
SELECT * FROM general_summary
ORDER BY 
  CASE 
    WHEN group_name = 'General' THEN 5 
    ELSE CAST(SUBSTR(group_name, 2) AS INT64) 
  END;