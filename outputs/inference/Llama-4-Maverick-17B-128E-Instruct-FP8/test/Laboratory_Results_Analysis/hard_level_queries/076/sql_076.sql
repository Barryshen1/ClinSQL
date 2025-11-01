WITH 
-- Step 1: Filter male patients aged 87-97
eligible_patients AS (
  SELECT p.subject_id, p.anchor_age, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 87 AND 97
),

-- Step 2: Identify ACS patients
acs_patients AS (
  SELECT DISTINCT e.hadm_id
  FROM eligible_patients e
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON e.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Acute coronary syndrome%' OR dicd.long_title LIKE '%Myocardial infarction%'
),

-- Step 3: Calculate 72-hour lab instability score for ACS patients
lab_instability AS (
  WITH 
  icu_admissions AS (
    SELECT i.hadm_id, i.stay_id, i.intime
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    JOIN acs_patients a ON i.hadm_id = a.hadm_id
  ),
  lab_events AS (
    SELECT i.stay_id, l.charttime, l.itemid, l.valuenum
    FROM icu_admissions i
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON i.hadm_id = l.hadm_id
    WHERE l.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 72 HOUR)
  )
  SELECT stay_id, 
         STDDEV(valuenum) AS lab_instability_score
  FROM lab_events
  GROUP BY stay_id
),

-- Step 4: Calculate 95th percentile of lab instability score
percentile_95 AS (
  SELECT PERCENTILE_CONT(lab_instability_score, 0.95) AS p95
  FROM lab_instability
),

-- Step 5: Analyze patients >= P95
high_risk_patients AS (
  SELECT li.stay_id, i.hadm_id, i.intime, i.outtime, i.los, ad.hospital_expire_flag
  FROM lab_instability li
  JOIN percentile_95 p ON li.lab_instability_score >= p.p95
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON li.stay_id = i.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad ON i.hadm_id = ad.hadm_id
),

-- Step 6: Report mean LOS, in-hospital mortality, and compare avg critical lab events
analysis AS (
  SELECT 
    AVG(hrp.los) AS mean_los,
    AVG(CAST(hrp.hospital_expire_flag AS INT64)) AS in_hospital_mortality,
    (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.labevents` l JOIN high_risk_patients hrp2 ON l.hadm_id = hrp2.hadm_id) / COUNT(DISTINCT hrp.stay_id) AS avg_critical_lab_events
  FROM high_risk_patients hrp
)

-- Compare to general inpatients
SELECT 
  mean_los,
  in_hospital_mortality,
  avg_critical_lab_events,
  (SELECT AVG(los) FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS general_mean_los,
  (SELECT AVG(CAST(hospital_expire_flag AS INT64)) FROM `physionet-data.mimiciv_3_1_hosp.admissions`) AS general_in_hospital_mortality,
  (SELECT COUNT(*) FROM `physionet-data.mimiciv_3_1_hosp.labevents` l JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON l.hadm_id = i.hadm_id) / (SELECT COUNT(DISTINCT stay_id) FROM `physionet-data.mimiciv_3_1_icu.icustays`) AS general_avg_critical_lab_events
FROM analysis;