WITH 
-- Target population: Male patients aged 87-97 with ACS
target_population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    a.admittime, 
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 87 AND 97
    AND d.icd_code LIKE '%ACS%'  -- Simplified ACS identification
),

-- Lab events for target population within 72 hours of admission
lab_events_target AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.charttime, 
    le.itemid, 
    le.valuenum
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    target_population tp 
      ON le.subject_id = tp.subject_id AND le.hadm_id = tp.hadm_id
  WHERE 
    le.charttime BETWEEN tp.admittime AND TIMESTAMP_ADD(tp.admittime, INTERVAL 72 HOUR)
),

-- Calculate lab instability score (example: standard deviation of lab values)
lab_instability AS (
  SELECT 
    subject_id, 
    hadm_id, 
    STDEV(valuenum) AS lab_instability_score
  FROM 
    lab_events_target
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Calculate 95th percentile of lab instability score
p95_score AS (
  SELECT 
    APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(95)] AS p95
  FROM 
    lab_instability
),

-- Identify patients with lab instability score >= 95th percentile
high_risk_patients AS (
  SELECT 
    li.subject_id, 
    li.hadm_id, 
    li.lab_instability_score
  FROM 
    lab_instability li
  CROSS JOIN 
    p95_score p95
  WHERE 
    li.lab_instability_score >= p95.p95
),

-- Calculate mean LOS, in-hospital mortality for high-risk patients
high_risk_stats AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)) / 24 AS mean_LOS,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    high_risk_patients hrp 
      ON a.hadm_id = hrp.hadm_id
),

-- General inpatient stats for comparison
general_inpatient_stats AS (
  SELECT 
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)) / 24 AS mean_LOS_general,
    SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(*) AS in_hospital_mortality_general
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 87 AND 97
),

-- Critical lab events per patient
critical_lab_events AS (
  SELECT 
    subject_id, 
    hadm_id, 
    COUNT(*) AS critical_lab_events
  FROM 
    lab_events_target
  WHERE 
    valuenum > (SELECT highnormalvalue FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` WHERE itemid = lab_events_target.itemid)
  GROUP BY 
    subject_id, 
    hadm_id
)

-- Final output
SELECT 
  hrp.lab_instability_score,
  hrs.mean_LOS,
  hrs.in_hospital_mortality,
  COALESCE(AVG(cle.critical_lab_events), 0) AS avg_critical_lab_events,
  gi.mean_LOS_general,
  gi.in_hospital_mortality_general
FROM 
  high_risk_patients hrp
  JOIN high_risk_stats hrs ON hrp.hadm_id = hrs.hadm_id
  LEFT JOIN critical_lab_events cle ON hrp.hadm_id = cle.hadm_id
  CROSS JOIN general_inpatient_stats gi
GROUP BY 
  hrp.lab_instability_score,
  hrs.mean_LOS,
  hrs.in_hospital_mortality,
  gi.mean_LOS_general,
  gi.in_hospital_mortality_general;