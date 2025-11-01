WITH patients_with_hh AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 50 AND 60
  AND dicd.long_title LIKE '%Hyperosmolar hyperglycemic state%'
),
lab_events AS (
  SELECT le.hadm_id, le.itemid, le.charttime, le.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN patients_with_hh p ON le.hadm_id = p.hadm_id
  WHERE le.charttime <= TIMESTAMP_ADD(p.admittime, INTERVAL 48 HOUR)
),
lab_instability AS (
  SELECT hadm_id, COUNT(CASE WHEN itemid = 50813 AND valuenum > 4 THEN 1 END) AS instability_score
  FROM lab_events
  GROUP BY hadm_id
),
percentile_75 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(75)] AS threshold
  FROM lab_instability
),
high_risk_admissions AS (
  SELECT li.hadm_id
  FROM lab_instability li
  WHERE li.instability_score >= (SELECT threshold FROM percentile_75)
),
admission_outcomes AS (
  SELECT 
    a.hadm_id,
    a.dischtime - a.admittime AS los,
    a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
),
high_risk_outcomes AS (
  SELECT 
    hra.hadm_id,
    ao.los,
    ao.hospital_expire_flag,
    (SELECT COUNT(CASE WHEN le.itemid = 50813 AND le.valuenum > 4 THEN 1 END) 
     FROM lab_events le WHERE le.hadm_id = hra.hadm_id) AS count_critical_labs
  FROM high_risk_admissions hra
  JOIN admission_outcomes ao ON hra.hadm_id = ao.hadm_id
)
SELECT 
  AVG(hospital_expire_flag) AS mortality_high_risk,
  AVG(los) AS mean_los_high_risk,
  AVG(count_critical_labs) AS mean_critical_labs_high_risk,
  (SELECT AVG(count_critical_labs) FROM high_risk_outcomes) AS mean_critical_labs_general
FROM high_risk_outcomes;