WITH 
-- Step 1: Filter patients of interest
patients_of_interest AS (
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
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 52 AND 62
    AND a.admission_type = 'Emergency'
),

-- Step 2: Identify asthma exacerbation cases
asthma_exacerbation AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code LIKE '493%'
),

-- Step 3: Filter lab events within 72 hours of admission
lab_events_72hrs AS (
  SELECT 
    le.subject_id, 
    le.hadm_id, 
    le.charttime, 
    le.valuenum, 
    le.valueuom,
    dli.label
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_labitems` dli 
      ON le.itemid = dli.itemid
  JOIN 
    patients_of_interest pio 
      ON le.hadm_id = pio.hadm_id
  WHERE 
    le.charttime BETWEEN 
      pio.admittime 
      AND TIMESTAMP_ADD(pio.admittime, INTERVAL 72 HOUR)
),

-- Step 4: Calculate lab instability score (simple standard deviation as a proxy)
lab_instability_score AS (
  SELECT 
    subject_id, 
    hadm_id, 
    STDDEV(valuenum) AS lab_instability_score
  FROM 
    lab_events_72hrs
  GROUP BY 
    subject_id, 
    hadm_id
  HAVING 
    COUNT(valuenum) > 1
),

-- Step 5: Calculate 90th percentile lab instability score
percentile_score AS (
  SELECT 
    PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY lab_instability_score) AS percentile_90_score
  FROM 
    lab_instability_score
),

-- Step 6: Identify top decile patients by lab instability score
top_decile AS (
  SELECT 
    subject_id, 
    hadm_id, 
    lab_instability_score,
    PERCENT_RANK() OVER (ORDER BY lab_instability_score) AS percentile
  FROM 
    lab_instability_score
),

-- Step 7: Filter top decile patients
top_decile_patients AS (
  SELECT 
    subject_id, 
    hadm_id, 
    lab_instability_score
  FROM 
    top_decile
  WHERE 
    percentile <= 0.1
),

-- Step 8: Calculate outcomes for top decile patients
top_decile_outcomes AS (
  SELECT 
    tdp.subject_id, 
    tdp.hadm_id,
    COALESCE(pio.hospital_expire_flag, 0) AS mortality,
    TIMESTAMP_DIFF(pio.dischtime, pio.admittime, DAY) AS los,
    COUNT(DISTINCT le.itemid) AS critical_lab_events
  FROM 
    top_decile_patients tdp
  JOIN 
    patients_of_interest pio 
      ON tdp.hadm_id = pio.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON tdp.hadm_id = le.hadm_id
  GROUP BY 
    tdp.subject_id, 
    tdp.hadm_id,
    pio.hospital_expire_flag,
    pio.dischtime,
    pio.admittime
),

-- Step 9: Age-matched males for comparison
age_matched_males AS (
  SELECT 
    poi.subject_id,
    poi.hadm_id,
    COALESCE(a.hospital_expire_flag, 0) AS mortality,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los,
    COUNT(DISTINCT le.itemid) AS critical_lab_events
  FROM 
    patients_of_interest poi
  JOIN 
    asthma_exacerbation ae 
      ON poi.subject_id = ae.subject_id AND poi.hadm_id = ae.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON poi.hadm_id = a.hadm_id
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.labevents` le 
      ON poi.hadm_id = le.hadm_id
  GROUP BY 
    poi.subject_id,
    poi.hadm_id,
    a.hospital_expire_flag,
    a.dischtime,
    a.admittime
)

-- Final query
SELECT 
  'Top Decile' AS group_name,
  AVG(mortality) AS avg_mortality,
  AVG(los) AS avg_los,
  AVG(critical_lab_events) AS avg_critical_lab_events
FROM 
  top_decile_outcomes

UNION ALL

SELECT 
  'Age-Matched Males' AS group_name,
  AVG(mortality) AS avg_mortality,
  AVG(los) AS avg_los,
  AVG(critical_lab_events) AS avg_critical_lab_events
FROM 
  age_matched_males;