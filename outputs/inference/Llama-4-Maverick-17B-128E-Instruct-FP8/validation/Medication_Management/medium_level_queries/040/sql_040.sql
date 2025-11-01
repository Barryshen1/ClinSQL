WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 36 AND 46
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Diabetes%')
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` WHERE long_title LIKE '%Heart failure%')
  )
),

-- Step 2: Analyze medication usage in the first 48 hours and last 12 hours
meds AS (
  SELECT c.subject_id, c.hadm_id,
         CASE 
           WHEN p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR) THEN 'First 48h'
           WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR) AND c.dischtime THEN 'Last 12h'
           ELSE 'Other'
         END AS time_window,
         -- Identify antidiabetic and cardiac drugs
         CASE 
           WHEN LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Antidiabetic'
           WHEN LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%beta blocker%' OR LOWER(p.drug) LIKE '%ace inhibitor%' THEN 'Cardiac'
           ELSE 'Other'
         END AS drug_class
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND c.dischtime
  AND (LOWER(p.drug) LIKE '%metformin%' OR LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%glimepiride%' 
       OR LOWER(p.drug) LIKE '%aspirin%' OR LOWER(p.drug) LIKE '%beta blocker%' OR LOWER(p.drug) LIKE '%ace inhibitor%')
),

-- Step 3: Calculate prevalence
prevalence AS (
  SELECT drug_class, time_window, COUNT(DISTINCT hadm_id) AS num_patients
  FROM meds
  WHERE time_window IN ('First 48h', 'Last 12h')
  GROUP BY drug_class, time_window
),

-- Step 4: Calculate percentages and differences
percentages AS (
  SELECT drug_class, 
         SUM(CASE WHEN time_window = 'First 48h' THEN num_patients ELSE 0 END) / (SELECT COUNT(*) FROM cohort) * 100 AS pct_first_48h,
         SUM(CASE WHEN time_window = 'Last 12h' THEN num_patients ELSE 0 END) / (SELECT COUNT(*) FROM cohort) * 100 AS pct_last_12h
  FROM prevalence
  GROUP BY drug_class
)

-- Final output
SELECT drug_class, 
       pct_first_48h, 
       pct_last_12h, 
       pct_last_12h - pct_first_48h AS abs_diff_pp
FROM percentages
ORDER BY drug_class;