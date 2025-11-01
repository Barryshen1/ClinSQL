WITH 
-- Step 1: Filter patients of interest
patients_of_interest AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    a.admittime,
    i.intime,
    i.outtime,
    i.first_careunit,
    i.last_careunit,
    p.anchor_age,
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON i.hadm_id = a.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 45 AND 55
),

-- Step 2: Identify ARF patients (Using ICD-10 codes as MIMIC-IV primarily uses them)
arf_patients AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id
  FROM 
    patients_of_interest
  WHERE 
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE hadm_id = patients_of_interest.hadm_id
      AND icd_code LIKE '%J32%'  -- Acute respiratory failure
    )
),

-- Step 3: Calculate vital sign instability scores in the first 48h
vital_signs AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM 
    `physionet-data.mimiciv_3_1_icu.chartevents`
  WHERE 
    stay_id IN (SELECT stay_id FROM arf_patients)
    AND charttime BETWEEN intime AND intime + INTERVAL 48 HOUR
    AND itemid IN (SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` 
                   WHERE category IN ('Vital Signs'))
),

-- Step 4: Calculate composite instability score (example)
instability_scores AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    STDEV(valuenum) AS instability_score
  FROM 
    vital_signs
  WHERE 
    itemid = 220050  -- Heart Rate
  GROUP BY 
    subject_id, hadm_id, stay_id
)

-- Step 5: Find 95th percentile 
SELECT 
  APPROX_QUANTILES(instability_score, 0.95) AS percentile_95
FROM 
  instability_scores;