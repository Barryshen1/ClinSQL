WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.transfers` t ON a.hadm_id = t.hadm_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 53 AND 63
  AND t.careunit = 'Step-Down Unit'
),

-- Step 2: Identify patients who received invasive mechanical ventilation
ventilated_patients AS (
  SELECT DISTINCT pe.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.procedureevents` pe
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON pe.itemid = di.itemid
  WHERE di.label LIKE '%Invasive Ventilation%'  
),

-- Step 3: Get nighttime SBP measurements for the cohort
sbp_measurements AS (
  SELECT ce.hadm_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di ON ce.itemid = di.itemid
  WHERE di.label LIKE '%Systolic Blood Pressure%'  
  AND EXTRACT(HOUR FROM ce.charttime) BETWEEN 0 AND 5  
  AND ce.hadm_id IN (SELECT hadm_id FROM cohort)
  AND ce.hadm_id IN (SELECT hadm_id FROM ventilated_patients)
)

-- Step 4: Calculate the standard deviation of SBP measurements
SELECT STDDEV(valuenum) AS sbp_stddev
FROM sbp_measurements;