WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, a.hadm_id, icu.stay_id, 
         p.gender, 
         p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON a.hadm_id = icu.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 51 AND 61
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 9 AND icd_code IN ('250.00', '250.01', '250.02', '250.03')  -- Simplified diabetes ICD-9 codes
    OR icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^E10|E11|E13')  -- Simplified diabetes ICD-10 codes
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_version = 9 AND icd_code LIKE '428%'  -- Simplified heart failure ICD-9 codes
    OR icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I50')  -- Simplified heart failure ICD-10 codes
  )
),

-- Step 2: Determine insulin therapy
insulin_therapy AS (
  SELECT i.stay_id, i.starttime, i.itemid, di.label,
         CASE 
           WHEN di.label LIKE '%basal%' THEN 'Basal'
           WHEN di.label LIKE '%bolus%' THEN 'Bolus'
           WHEN di.label LIKE '%sliding%' THEN 'Sliding-scale'
           ELSE 'Other'
         END AS insulin_type
  FROM `physionet-data.mimiciv_3_1_icu.inputevents` i
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON i.itemid = di.itemid
  WHERE di.label LIKE '%insulin%' AND i.stay_id IN (SELECT stay_id FROM cohort)
),

-- Step 3: Calculate prevalence in first 24h and final 12h
insulin_prevalence AS (
  SELECT it.stay_id, 
         MAX(CASE WHEN it.starttime <= (icu.intime + INTERVAL 24 HOUR) THEN it.insulin_type END) AS first_24h,
         MAX(CASE WHEN it.starttime >= (icu.outtime - INTERVAL 12 HOUR) THEN it.insulin_type END) AS final_12h
  FROM insulin_therapy it
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON it.stay_id = icu.stay_id
  GROUP BY it.stay_id
),

-- Step 4: Compute percentage-point change
prevalence_calc AS (
  SELECT 
    COUNT(CASE WHEN first_24h IN ('Basal', 'Bolus') THEN 1 END) * 100.0 / COUNT(*) AS basal_bolus_first_24h,
    COUNT(CASE WHEN final_12h IN ('Basal', 'Bolus') THEN 1 END) * 100.0 / COUNT(*) AS basal_bolus_final_12h,
    COUNT(CASE WHEN first_24h = 'Basal' THEN 1 END) * 100.0 / COUNT(*) AS basal_first_24h,
    COUNT(CASE WHEN final_12h = 'Basal' THEN 1 END) * 100.0 / COUNT(*) AS basal_final_12h,
    COUNT(CASE WHEN first_24h = 'Bolus' THEN 1 END) * 100.0 / COUNT(*) AS bolus_first_24h,
    COUNT(CASE WHEN final_12h = 'Bolus' THEN 1 END) * 100.0 / COUNT(*) AS bolus_final_12h,
    COUNT(CASE WHEN first_24h = 'Sliding-scale' THEN 1 END) * 100.0 / COUNT(*) AS sliding_scale_first_24h,
    COUNT(CASE WHEN final_12h = 'Sliding-scale' THEN 1 END) * 100.0 / COUNT(*) AS sliding_scale_final_12h
  FROM insulin_prevalence
)

SELECT 
  'Basal-Bolus' AS insulin_type,
  basal_bolus_first_24h,
  basal_bolus_final_12h,
  basal_bolus_final_12h - basal_bolus_first_24h AS percentage_point_change
FROM prevalence_calc
UNION ALL
SELECT 
  'Basal',
  basal_first_24h,
  basal_final_12h,
  basal_final_12h - basal_first_24h
FROM prevalence_calc
UNION ALL
SELECT 
  'Bolus',
  bolus_first_24h,
  bolus_final_12h,
  bolus_final_12h - bolus_first_24h
FROM prevalence_calc
UNION ALL
SELECT 
  'Sliding-scale',
  sliding_scale_first_24h,
  sliding_scale_final_12h,
  sliding_scale_final_12h - sliding_scale_first_24h
FROM prevalence_calc;