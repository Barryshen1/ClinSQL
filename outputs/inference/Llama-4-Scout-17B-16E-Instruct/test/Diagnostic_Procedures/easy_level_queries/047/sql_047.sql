WITH 
  -- Filter patients of interest (42-year-old male, among men 37–47)
  patients_of_interest AS (
    SELECT subject_id
    FROM `physionet-data.mimiciv_3_1_hosp.patients`
    WHERE gender = 'M' AND anchor_age BETWEEN 37 AND 47
  ),
  
  -- Identify hospital admissions for patients of interest
  admissions_of_interest AS (
    SELECT a.hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN patients_of_interest p ON a.subject_id = p.subject_id
  ),
  
  -- Identify procedures of interest (catheter ablation or cardioversion)
  procedures_of_interest AS (
    SELECT hadm_id, COUNT(DISTINCT icd_code) as num_procedures
    FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd`
    WHERE hadm_id IN (SELECT hadm_id FROM admissions_of_interest)
    AND icd_code IN (
      SELECT icd_code
      FROM `physionet-data.mimiciv_3_1_hosp.d_icd_procedures`
      WHERE long_title IN ('Catheter ablation', 'Cardioversion')
    )
    GROUP BY hadm_id
  )

-- Calculate the standard deviation of distinct procedures
SELECT 
  stddev(num_procedures) AS sd_distinct_procedures
FROM procedures_of_interest;