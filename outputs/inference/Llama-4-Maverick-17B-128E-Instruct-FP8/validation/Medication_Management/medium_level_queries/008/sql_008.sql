WITH 
-- Step 1: Identify the cohort based on age, gender, and diagnoses
cohort AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F' AND p.anchor_age BETWEEN 44 AND 54
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code IN ('E11', 'E11.9')  -- Simplified T2DM ICD-10 codes for illustration
  )
  AND a.hadm_id IN (
    SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
    WHERE icd_code LIKE 'I50%'  -- Heart failure ICD-10 codes
  )
),

-- Step 2: Identify medication usage within the first 24h and last 48h
meds_first_24h AS (
  SELECT c.hadm_id, 
         SUM(CASE WHEN LOWER(drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_count,
         SUM(CASE WHEN LOWER(drug) LIKE '%metformin%' OR LOWER(drug) LIKE '%sulfonylurea%' THEN 1 ELSE 0 END) AS oral_agent_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND (c.admittime + INTERVAL 1 DAY)
  GROUP BY c.hadm_id
),

meds_last_48h AS (
  SELECT c.hadm_id, 
         SUM(CASE WHEN LOWER(drug) LIKE '%insulin%' THEN 1 ELSE 0 END) AS insulin_count,
         SUM(CASE WHEN LOWER(drug) LIKE '%metformin%' OR LOWER(drug) LIKE '%sulfonylurea%' THEN 1 ELSE 0 END) AS oral_agent_count
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN (c.dischtime - INTERVAL 2 DAY) AND c.dischtime
  GROUP BY c.hadm_id
),

-- Step 3: Compare prevalence and calculate continued/initiated/discontinued counts
comparison AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN m1.insulin_count > 0 THEN m1.hadm_id END) AS insulin_first_24h,
    COUNT(DISTINCT CASE WHEN m1.oral_agent_count > 0 THEN m1.hadm_id END) AS oral_agent_first_24h,
    COUNT(DISTINCT CASE WHEN m2.insulin_count > 0 THEN m2.hadm_id END) AS insulin_last_48h,
    COUNT(DISTINCT CASE WHEN m2.oral_agent_count > 0 THEN m2.hadm_id END) AS oral_agent_last_48h,
    COUNT(DISTINCT CASE WHEN m1.insulin_count > 0 AND m2.insulin_count > 0 THEN m1.hadm_id END) AS insulin_continued,
    COUNT(DISTINCT CASE WHEN m1.insulin_count = 0 AND m2.insulin_count > 0 THEN m2.hadm_id END) AS insulin_initiated,
    COUNT(DISTINCT CASE WHEN m1.insulin_count > 0 AND m2.insulin_count = 0 THEN m1.hadm_id END) AS insulin_discontinued,
    COUNT(DISTINCT CASE WHEN m1.oral_agent_count > 0 AND m2.oral_agent_count > 0 THEN m1.hadm_id END) AS oral_agent_continued,
    COUNT(DISTINCT CASE WHEN m1.oral_agent_count = 0 AND m2.oral_agent_count > 0 THEN m2.hadm_id END) AS oral_agent_initiated,
    COUNT(DISTINCT CASE WHEN m1.oral_agent_count > 0 AND m2.oral_agent_count = 0 THEN m1.hadm_id END) AS oral_agent_discontinued
  FROM meds_first_24h m1
  FULL OUTER JOIN meds_last_48h m2 ON m1.hadm_id = m2.hadm_id
)

-- Final output
SELECT 
  'Insulin' AS medication_type,
  insulin_first_24h, insulin_last_48h, insulin_continued, insulin_initiated, insulin_discontinued
FROM comparison
UNION ALL
SELECT 
  'Oral Agent' AS medication_type,
  oral_agent_first_24h, oral_agent_last_48h, oral_agent_continued, oral_agent_initiated, oral_agent_discontinued
FROM comparison;