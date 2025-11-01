WITH 
-- Step 1: Identify DKA patients
dka_patients AS (
  SELECT DISTINCT d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd 
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE dicd.long_title LIKE '%Diabetic ketoacidosis%' 
    AND d.icd_version = 9  
),
-- Step 2: Filter cohort by age and gender
cohort AS (
  SELECT p.subject_id, a.hadm_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 39 AND 49
),
-- Step 3 & 5: Calculate 30-day mortality and LOS
mortality_los AS (
  SELECT 
    c.hadm_id,
    c.anchor_age,
    CASE 
      WHEN a.deathtime <= DATE_ADD(a.admittime, INTERVAL 30 DAY) THEN 1
      WHEN a.dischtime <= DATE_ADD(a.admittime, INTERVAL 30 DAY) AND a.deathtime IS NULL THEN 0
      ELSE 0  
    END AS thirty_day_mortality,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
),
-- Complications
complications AS (
  SELECT DISTINCT d.hadm_id, 
    CASE WHEN dicd.long_title LIKE '%Cardiac%' OR dicd.long_title LIKE '%Myocardial%' THEN 1 ELSE 0 END AS cardiovascular_complication,
    CASE WHEN dicd.long_title LIKE '%Neurological%' THEN 1 ELSE 0 END AS neurologic_complication
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd 
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
),
-- Calculate risk percentile
risk_percentile AS (
  SELECT 
    ml.hadm_id,
    PERCENT_RANK() OVER (ORDER BY ml.thirty_day_mortality) AS risk_percentile
  FROM mortality_los ml
)

-- Final query
SELECT 
  AVG(CASE WHEN c.hadm_id IN (SELECT hadm_id FROM dka_patients) THEN ml.thirty_day_mortality ELSE NULL END) AS dka_30day_mortality,
  AVG(CASE WHEN c.hadm_id NOT IN (SELECT hadm_id FROM dka_patients) THEN ml.thirty_day_mortality ELSE NULL END) AS non_dka_30day_mortality,
  AVG(CASE WHEN c.hadm_id IN (SELECT hadm_id FROM dka_patients) AND ml.los > 0 THEN ml.los ELSE NULL END) AS dka_los,
  AVG(CASE WHEN c.hadm_id NOT IN (SELECT hadm_id FROM dka_patients) AND ml.los > 0 THEN ml.los ELSE NULL END) AS non_dka_los,
  AVG(CASE WHEN c.hadm_id IN (SELECT hadm_id FROM dka_patients) THEN comp.cardiovascular_complication ELSE NULL END) AS dka_cardiovascular_complication_rate,
  AVG(CASE WHEN c.hadm_id IN (SELECT hadm_id FROM dka_patients) THEN comp.neurologic_complication ELSE NULL END) AS dka_neurologic_complication_rate,
  -- Filter for a specific patient profile (e.g., 44-year-old with DKA) to get the risk percentile
  (SELECT rp.risk_percentile FROM risk_percentile rp JOIN cohort c2 ON rp.hadm_id = c2.hadm_id WHERE c2.anchor_age = 44 AND c2.hadm_id IN (SELECT hadm_id FROM dka_patients) LIMIT 1) AS risk_percentile_for_dka_44yo
FROM cohort c
JOIN mortality_los ml ON c.hadm_id = ml.hadm_id
LEFT JOIN complications comp ON c.hadm_id = comp.hadm_id;