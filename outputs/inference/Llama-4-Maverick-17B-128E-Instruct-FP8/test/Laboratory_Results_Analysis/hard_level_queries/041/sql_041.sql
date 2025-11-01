WITH 
-- Step 1: Identify the cohort
heart_failure_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag
    ON d.icd_code = diag.icd_code AND d.icd_version = diag.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON d.subject_id = p.subject_id
  WHERE diag.long_title LIKE '%Heart failure%' 
    AND p.gender = 'M' 
    AND p.anchor_age BETWEEN 54 AND 64
),

-- Step 2: Calculate laboratory instability score in the first 48 hours
lab_values AS (
  SELECT c.stay_id, c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  INNER JOIN heart_failure_patients hfp
    ON i.hadm_id = hfp.hadm_id
  WHERE c.itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Lactate')
    AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 48 HOUR)
),

lab_instability AS (
  SELECT stay_id, 
         STDDEV(valuenum) AS instability_score
  FROM lab_values
  GROUP BY stay_id
),

-- Step 3: Determine the 95th percentile of the laboratory instability score
percentile_95 AS (
  SELECT APPROX_QUANTILES(instability_score, 100)[OFFSET(95)] AS threshold
  FROM lab_instability
),

-- Step 4: For patients ≥ that threshold, report in-hospital mortality, mean LOS
high_instability_outcomes AS (
  SELECT 
    a.hospital_expire_flag AS in_hospital_mortality,
    i.los AS icu_los,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS hospital_los
  FROM lab_instability l
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON l.stay_id = i.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON i.hadm_id = a.hadm_id
  WHERE l.instability_score >= (SELECT threshold FROM percentile_95)
)

-- Reporting
SELECT 
  AVG(in_hospital_mortality) AS mean_in_hospital_mortality,
  AVG(icu_los) AS mean_icu_los,
  AVG(hospital_los) AS mean_hospital_los
FROM high_instability_outcomes;