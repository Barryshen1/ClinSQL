WITH 
-- Define T2DM and heart failure ICD codes
t2dm_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Type 2 diabetes mellitus%'
),
heart_failure_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE long_title LIKE '%Heart failure%'
),

-- Identify relevant patients
patients_relevant AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
  ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
  AND p.anchor_age BETWEEN 44 AND 54
  AND a.hadm_id IN (
    SELECT hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code IN (SELECT icd_code FROM t2dm_icd)
    OR icd_code IN (SELECT icd_code FROM heart_failure_icd)
  )
),

-- Identify insulin and oral agent prescriptions in first 24h and last 48h
prescriptions_with_admissions AS (
  SELECT p.hadm_id, p.starttime, a.admittime, a.dischtime,
         CASE WHEN p.drug LIKE '%insulin%' THEN 'insulin' 
              WHEN p.drug NOT LIKE '%insulin%' AND p.drug LIKE '%diabetes%' THEN 'oral_agent' 
              ELSE 'other' END AS drug_category
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN patients_relevant a ON p.hadm_id = a.hadm_id
),

first_24h AS (
  SELECT hadm_id,
         SUM(CASE WHEN drug_category = 'insulin' THEN 1 ELSE 0 END) AS insulin_count,
         SUM(CASE WHEN drug_category = 'oral_agent' THEN 1 ELSE 0 END) AS oral_agent_count
  FROM prescriptions_with_admissions
  WHERE starttime BETWEEN admittime AND admittime + INTERVAL 1 DAY
  GROUP BY hadm_id
),

last_48h AS (
  SELECT hadm_id,
         SUM(CASE WHEN drug_category = 'insulin' THEN 1 ELSE 0 END) AS insulin_count,
         SUM(CASE WHEN drug_category = 'oral_agent' THEN 1 ELSE 0 END) AS oral_agent_count
  FROM prescriptions_with_admissions
  WHERE starttime BETWEEN dischtime - INTERVAL 2 DAY AND dischtime
  GROUP BY hadm_id
)

-- Final calculation
SELECT 
  COALESCE(f.insulin_count, 0) AS first_24h_insulin_count,
  COALESCE(f.oral_agent_count, 0) AS first_24h_oral_agent_count,
  COALESCE(l.insulin_count, 0) AS last_48h_insulin_count,
  COALESCE(l.oral_agent_count, 0) AS last_48h_oral_agent_count
FROM 
  (SELECT hadm_id, insulin_count, oral_agent_count FROM first_24h) f
FULL OUTER JOIN 
  (SELECT hadm_id, insulin_count, oral_agent_count FROM last_48h) l
ON f.hadm_id = l.hadm_id;