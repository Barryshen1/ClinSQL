WITH base_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime, 
    adm.hospital_expire_flag,
    p.gender,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) BETWEEN 48 AND 58
),
hemorrhagic_stroke AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code IN ('430', '431', '432')) OR
    (icd_version = 10 AND icd_code LIKE 'I6[0-2]%')
),
base_with_stroke AS (
  SELECT 
    ba.*,
    CASE WHEN hs.hadm_id IS NOT NULL THEN 1 ELSE 0 END AS is_hemorrhagic_stroke
  FROM base_admissions ba
  LEFT JOIN hemorrhagic_stroke hs
    ON ba.hadm_id = hs.hadm_id
),
lab_events_critical AS (
  SELECT 
    le.hadm_id,
    COUNT(le.labevent_id) AS total_critical_labs,
    COUNT(DISTINCT dlab.category) AS instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dlab
    ON le.itemid = dlab.itemid
  INNER JOIN base_with_stroke bws
    ON le.hadm_id = bws.hadm_id
  WHERE 
    le.charttime BETWEEN bws.admittime AND DATETIME_ADD(bws.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL
  GROUP BY le.hadm_id
),
base_with_labs AS (
  SELECT 
    bws.*,
    COALESCE(lab.total_critical_labs, 0) AS total_critical_labs,
    COALESCE(lab.instability_score, 0) AS instability_score
  FROM base_with_stroke bws
  LEFT JOIN lab_events_critical lab
    ON bws.hadm_id = lab.hadm_id
),
percentile_90 AS (
  SELECT 
    APPROX_QUANTILES(instability_score, 100)[OFFSET(90)] AS p90_score
  FROM base_with_labs
  WHERE is_hemorrhagic_stroke = 1
),
high_score_group AS (
  SELECT 
    'High-score hemorrhagic stroke' AS group_name,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days,
    AVG(total_critical_labs) AS avg_critical_labs
  FROM base_with_labs
  WHERE is_hemorrhagic_stroke = 1
    AND instability_score >= (SELECT p90_score FROM percentile_90)
),
control_group AS (
  SELECT 
    'Control (no hemorrhagic stroke)' AS group_name,
    COUNT(*) AS total_patients,
    SUM(hospital_expire_flag) AS deaths,
    AVG(DATETIME_DIFF(dischtime, admittime, SECOND) / 86400.0) AS mean_los_days,
    AVG(total_critical_labs) AS avg_critical_labs
  FROM base_with_labs
  WHERE is_hemorrhagic_stroke = 0
)
SELECT 
  group_name,
  total_patients,
  deaths * 100.0 / total_patients AS mortality_percent,
  mean_los_days,
  avg_critical_labs
FROM (
  SELECT * FROM high_score_group
  UNION ALL
  SELECT * FROM control_group
);