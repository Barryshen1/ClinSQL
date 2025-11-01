WITH 
-- Step 1: Identify patients and their admission details
patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,  -- Added admittime here
    a.dischtime,
    p.dod
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' AND p.anchor_age BETWEEN 63 AND 73
),

-- Step 2: Count diagnoses for each admission
diagnosis_count AS (
  SELECT 
    hadm_id, 
    COUNT(*) as num_diagnoses
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY 
    hadm_id
),

-- Step 3: Identify septic shock patients (simplified, actual implementation may vary)
septic_shock AS (
  -- For simplicity, let's assume we're checking for a specific ICD code indicative of septic shock
  SELECT DISTINCT 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code = 'R65.21'  -- Example code for septic shock
),

-- Step 4: Calculate 90-day mortality and LOS
cohort_outcomes AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.dischtime,
    pa.dod,
    DATE_DIFF(pa.dod, pa.dischtime, DAY) AS survival_days,
    DATE_DIFF(pa.dischtime, pa.admittime, DAY) AS los_hospital
  FROM 
    patient_admissions pa
  JOIN 
    diagnosis_count dc ON pa.hadm_id = dc.hadm_id
  JOIN 
    septic_shock ss ON pa.hadm_id = ss.hadm_id
  WHERE 
    dc.num_diagnoses > 15
)

-- Final calculations
SELECT 
  AVG(CASE WHEN survival_days <= 90 THEN 1 ELSE 0 END) AS mortality_90day,
  AVG(los_hospital) AS mean_los
FROM 
  cohort_outcomes
WHERE 
  survival_days IS NOT NULL OR dod IS NULL  -- To handle patients who were alive at the end of the study;