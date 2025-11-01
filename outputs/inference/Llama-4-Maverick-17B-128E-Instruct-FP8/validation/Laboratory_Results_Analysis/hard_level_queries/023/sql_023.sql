WITH 
-- Step 1: Identify AMI patients and filter by age and gender
ami_patients AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 90 AND 100
    AND icd.long_title LIKE '%Acute myocardial infarction%'
),

-- Step 2: Calculate lab-instability score for the first 48 hours
lab_instability AS (
  SELECT a.hadm_id, 
         -- Example: calculating standard deviation of a specific lab measurement (e.g., creatinine)
         STDDEV(valuenum) AS lab_instability_score
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN ami_patients a ON l.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE dl.label = 'Creatinine'  -- Example lab measurement
    AND l.charttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
  GROUP BY a.hadm_id
),

-- Step 3: Calculate 75th percentile of lab-instability score
percentiles AS (
  SELECT APPROX_QUANTILES(lab_instability_score, 100)[OFFSET(75)] AS p75_lab_instability
  FROM lab_instability
),

-- Step 4: Analyze outcomes for ≥P75 patients versus all inpatients
outcomes AS (
  SELECT 
    a.hadm_id,
    a.deathtime IS NOT NULL OR a.hospital_expire_flag = 1 AS in_hospital_mortality,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) / 24.0 AS los,
    -- Example critical lab condition (e.g., creatinine > 2)
    MAX(CASE WHEN l.valuenum > 2 AND dl.label = 'Creatinine' THEN 1 ELSE 0 END) AS critical_lab
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l ON a.hadm_id = l.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl ON l.itemid = dl.itemid
  WHERE a.hadm_id IN (SELECT hadm_id FROM ami_patients)
  GROUP BY a.hadm_id, a.deathtime, a.hospital_expire_flag, a.dischtime, a.admittime
)

SELECT 
  '>=P75' AS cohort,
  COUNT(CASE WHEN in_hospital_mortality THEN 1 END) / COUNT(*) AS in_hospital_mortality_rate,
  AVG(los) AS mean_los,
  COUNT(CASE WHEN critical_lab = 1 THEN 1 END) / COUNT(*) AS critical_lab_rate
FROM outcomes
WHERE hadm_id IN (SELECT hadm_id FROM lab_instability WHERE lab_instability_score >= (SELECT p75_lab_instability FROM percentiles))
UNION ALL
SELECT 
  'All 90-100' AS cohort,
  COUNT(CASE WHEN in_hospital_mortality THEN 1 END) / COUNT(*) AS in_hospital_mortality_rate,
  AVG(los) AS mean_los,
  COUNT(CASE WHEN critical_lab = 1 THEN 1 END) / COUNT(*) AS critical_lab_rate
FROM outcomes;