WITH 
-- Step 1: Identify female patients aged 40-50 with ACS
patients_of_interest AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.admission_type,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 40 AND 50
    AND a.admission_type = 'acute'
),

-- Step 2: Identify lab events for these patients within the first 48 hours
lab_events AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.itemid,
    le.valuenum,
    le.valueuom
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    patients_of_interest poi
  ON 
    le.subject_id = poi.subject_id AND le.hadm_id = poi.hadm_id
  WHERE 
    le.charttime BETWEEN poi.admittime AND TIMESTAMP_ADD(poi.admittime, INTERVAL 48 HOUR)
),

-- Step 3: Calculate a simple lab instability score (example: change in creatinine)
lab_instability AS (
  SELECT 
    subject_id,
    hadm_id,
    valuenum
  FROM 
    lab_events
  WHERE 
    itemid = 220050  -- Creatinine example
),

-- Step 4: Calculate 90th percentile of lab instability score
percentile_score AS (
  SELECT 
    APPROX_QUANTILES(valuenum, 0.9)[OFFSET(1)] AS percentile_90
  FROM 
    lab_instability
),

-- Step 5: Identify patients at or above the 90th percentile
threshold_patients AS (
  SELECT 
    li.subject_id,
    li.hadm_id,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag
  FROM 
    lab_instability li
  JOIN 
    patients_of_interest poi ON li.subject_id = poi.subject_id AND li.hadm_id = poi.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON li.hadm_id = a.hadm_id
  WHERE 
    li.valuenum >= (SELECT percentile_90 FROM percentile_score)
),

-- Step 6: Calculate outcomes for threshold patients
threshold_outcomes AS (
  SELECT 
    COUNT(DISTINCT tp.hadm_id) AS num_patients,
    SUM(CASE WHEN tp.deathtime IS NOT NULL OR tp.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT tp.hadm_id) AS mortality_rate,
    AVG(TIMESTAMP_DIFF(tp.dischtime, tp.admittime, DAY)) AS mean_LOS
  FROM 
    threshold_patients tp
),

-- Step 7: Calculate critical lab rate for threshold patients
critical_lab_rate AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN le.valuenum > 2 THEN le.hadm_id END) / COUNT(DISTINCT le.hadm_id) AS critical_rate
  FROM 
    lab_events le
  JOIN 
    threshold_patients tp ON le.hadm_id = tp.hadm_id
),

-- Step 8: Calculate general inpatient outcomes
general_outcomes AS (
  SELECT 
    COUNT(DISTINCT a.hadm_id) AS general_num_patients,
    SUM(CASE WHEN a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id) AS general_mortality_rate,
    AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY)) AS general_mean_LOS
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
)

-- Step 9: Report outcomes
SELECT 
  num_patients,
  mortality_rate,
  mean_LOS,
  (SELECT critical_rate FROM critical_lab_rate) AS critical_lab_rate,
  general_num_patients,
  general_mortality_rate,
  general_mean_LOS
FROM 
  threshold_outcomes,
  general_outcomes;