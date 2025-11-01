WITH stroke_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON di.icd_code = dd.icd_code AND di.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND dd.long_title LIKE '%hemorrhagic stroke%'
),
lab_instability AS (
  SELECT 
    sc.hadm_id,
    COUNT(DISTINCT dl.category) AS num_critical_lab_systems
  FROM stroke_cohort sc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sc.hadm_id = le.hadm_id
    AND le.charttime BETWEEN sc.admittime AND DATETIME_ADD(sc.admittime, INTERVAL 72 HOUR)
    AND le.flag IS NOT NULL  -- assuming flag indicates critical
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  GROUP BY sc.hadm_id
),
p90 AS (
  SELECT 
    APPROX_QUANTILES(num_critical_lab_systems, 100)[OFFSET(90)] AS p90_value
  FROM lab_instability
),
high_risk_stroke AS (
  SELECT 
    sc.*,
    li.num_critical_lab_systems,
    (SELECT p90_value FROM p90) AS p90_threshold
  FROM stroke_cohort sc
  INNER JOIN lab_instability li
    ON sc.hadm_id = li.hadm_id
  WHERE li.num_critical_lab_systems >= (SELECT p90_value FROM p90)
),
high_risk_metrics AS (
  SELECT 
    COUNT(*) AS n_high_risk,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    ROUND(AVG(los_days), 2) AS mean_los,
    ROUND(AVG(num_critical_lab_events), 2) AS avg_critical_labs_per_patient
  FROM (
    SELECT 
      hrs.hadm_id,
      hrs.hospital_expire_flag,
      hrs.los_days,
      (SELECT COUNT(*) 
       FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
       WHERE le.hadm_id = hrs.hadm_id 
         AND le.charttime BETWEEN hrs.admittime AND DATETIME_ADD(hrs.admittime, INTERVAL 72 HOUR)
         AND le.flag IS NOT NULL) AS num_critical_lab_events
    FROM high_risk_stroke hrs
  )
),
control_cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 48 AND 58
    AND a.hadm_id NOT IN (SELECT hadm_id FROM stroke_cohort)  -- exclude stroke patients
),
control_metrics AS (
  SELECT 
    COUNT(*) AS n_control,
    ROUND(100.0 * SUM(hospital_expire_flag) / COUNT(*), 2) AS mortality_percent,
    ROUND(AVG(los_days), 2) AS mean_los,
    ROUND(AVG(num_critical_lab_events), 2) AS avg_critical_labs_per_patient
  FROM (
    SELECT 
      cc.hadm_id,
      cc.hospital_expire_flag,
      cc.los_days,
      (SELECT COUNT(*) 
       FROM `physionet-data.mimiciv_3_1_hosp.labevents` le 
       WHERE le.hadm_id = cc.hadm_id 
         AND le.charttime BETWEEN cc.admittime AND DATETIME_ADD(cc.admittime, INTERVAL 72 HOUR)
         AND le.flag IS NOT NULL) AS num_critical_lab_events
    FROM control_cohort cc
  )
)
SELECT 
  'High-risk stroke cohort' AS cohort,
  n_high_risk AS n_patients,
  mortality_percent,
  mean_los,
  avg_critical_labs_per_patient
FROM high_risk_metrics
UNION ALL
SELECT 
  'Control cohort' AS cohort,
  n_control AS n_patients,
  mortality_percent,
  mean_los,
  avg_critical_labs_per_patient
FROM control_metrics;