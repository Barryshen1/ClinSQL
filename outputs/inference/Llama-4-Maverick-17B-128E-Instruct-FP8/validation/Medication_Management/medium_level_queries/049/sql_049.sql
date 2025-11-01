WITH 
-- Step 1: Identify the cohort
cohort AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 66 AND 76
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN ('250', 'E11', 'E10', 'E13', 'E14')  -- Simplified diabetes ICD-9/10 codes
        OR icd_code LIKE 'I50%'  -- Heart failure ICD-10 codes
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 96  -- Stay >= 96 hours to have at least 72h + 24h
),

-- Step 2: Extract antidiabetic medications in the first 72h and last 24h
medications AS (
  SELECT c.hadm_id, 
         p.drug,
         CASE 
           WHEN p.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 72 HOUR) THEN 'First 72h'
           WHEN p.starttime BETWEEN TIMESTAMP_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime THEN 'Last 24h'
         END AS time_period
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.drug_type = 'MAIN'  -- Focus on main drug prescriptions
    AND LOWER(p.drug) LIKE '%insulin%' OR LOWER(p.drug) LIKE '%metformin%'  -- Example antidiabetic drugs
),

-- Step 3: Calculate percentages for each antidiabetic class
percentages AS (
  SELECT time_period, 
         drug,
         COUNT(DISTINCT hadm_id) as num_admissions,
         COUNT(DISTINCT hadm_id) * 100.0 / (SELECT COUNT(DISTINCT hadm_id) FROM cohort) AS percentage
  FROM medications
  GROUP BY time_period, drug
)

-- Final output
SELECT drug, 
       SUM(CASE WHEN time_period = 'First 72h' THEN percentage ELSE 0 END) AS percentage_first_72h,
       SUM(CASE WHEN time_period = 'Last 24h' THEN percentage ELSE 0 END) AS percentage_last_24h
FROM percentages
GROUP BY drug
ORDER BY drug;