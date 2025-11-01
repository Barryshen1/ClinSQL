WITH 
-- Target population: Female AMI patients aged 90-100
target_population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 90 AND 100
    AND d.icd_code LIKE '410%'  -- AMI ICD code
),

-- Lab events in the first 48 hours
lab_events_48hrs AS (
  SELECT 
    tp.hadm_id, 
    COUNT(le.labevent_id) AS num_lab_tests
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON tp.hadm_id = le.hadm_id
      AND le.charttime BETWEEN tp.admittime AND TIMESTAMP_ADD(tp.admittime, INTERVAL 48 HOUR)
  GROUP BY 
    tp.hadm_id
),

-- Calculate 75th percentile of lab tests
p75 AS (
  SELECT 
    APPROX_QUANTILES(num_lab_tests, 1000)[75] AS p75_score
  FROM 
    lab_events_48hrs
),

-- Flag patients with scores >= P75
p75_patients AS (
  SELECT 
    hadm_id,
    CASE WHEN num_lab_tests >= (SELECT p75_score FROM p75) THEN 1 ELSE 0 END AS is_p75
  FROM 
    lab_events_48hrs
),

-- Outcomes for patients with scores >= P75 vs. all inpatients 90-100
outcomes AS (
  SELECT 
    tp.hadm_id,
    tp.hospital_expire_flag,
    DATE_DIFF(tp.dischtime, tp.admittime) AS los,
    p.is_p75
  FROM 
    target_population tp
  LEFT JOIN 
    p75_patients p ON tp.hadm_id = p.hadm_id
)

-- Final results
SELECT 
  'All Patients 90-100' AS population,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(hadm_id) AS in_hospital_mortality,
  AVG(los) AS mean_LOS
FROM 
  outcomes
UNION ALL
SELECT 
  '≥P75 Patients' AS population,
  SUM(CASE WHEN hospital_expire_flag = 1 AND is_p75 = 1 THEN 1 ELSE 0 END) / SUM(CASE WHEN is_p75 = 1 THEN 1 ELSE 0 END) AS in_hospital_mortality,
  AVG(los) AS mean_LOS
FROM 
  outcomes
WHERE 
  is_p75 = 1;