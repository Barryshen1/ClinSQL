WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 45 AND 55
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code IN ('250.0', '250.00', '250.01', '250.02', '250.03', 
                      '250.1', '250.10', '250.11', '250.12', '250.13', 
                      '428.0', '428.1', '428.2', '428.3', '428.4', 
                      '428.8', '428.9')
    )
),

-- Identify insulin and oral antidiabetic medications
medications AS (
  SELECT 
    p.subject_id, 
    p.hadm_id, 
    m.drug,
    m.starttime
  FROM 
    patients_of_interest p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` m 
      ON p.hadm_id = m.hadm_id
  WHERE 
    m.drug_type = 'medication'
    AND (m.drug LIKE '%insulin%' 
    OR m.drug LIKE '%glyburide%' 
    OR m.drug LIKE '%glipizide%' 
    OR m.drug LIKE '%metformin%')
),

-- First 12 hours medication
first_12_hours_medication AS (
  SELECT 
    m.hadm_id,
    COUNT(CASE WHEN m.drug LIKE '%insulin%' THEN 1 END) AS insulin_count,
    COUNT(CASE WHEN m.drug LIKE '%glyburide%' OR m.drug LIKE '%glipizide%' OR m.drug LIKE '%metformin%' THEN 1 END) AS oral_count
  FROM 
    medications m
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON m.hadm_id = i.hadm_id
  WHERE 
    m.starttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 12 HOUR)
  GROUP BY 
    m.hadm_id
),

-- Last 72 hours medication pre-discharge
last_72_hours_medication AS (
  SELECT 
    m.hadm_id,
    COUNT(CASE WHEN m.drug LIKE '%insulin%' THEN 1 END) AS insulin_count,
    COUNT(CASE WHEN m.drug LIKE '%glyburide%' OR m.drug LIKE '%glipizide%' OR m.drug LIKE '%metformin%' THEN 1 END) AS oral_count
  FROM 
    medications m
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON m.hadm_id = a.hadm_id
  WHERE 
    m.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 72 HOUR) AND a.dischtime
  GROUP BY 
    m.hadm_id
)

-- Calculate initiation rates and percentage point difference
SELECT 
  COALESCE(f12.insulin_count, 0) AS first_12h_insulin_rate,
  COALESCE(f12.oral_count, 0) AS first_12h_oral_rate,
  COALESCE(l72.insulin_count, 0) AS last_72h_insulin_rate,
  COALESCE(l72.oral_count, 0) AS last_72h_oral_rate,
  (COALESCE(f12.insulin_count, 0) - COALESCE(l72.insulin_count, 0)) AS pp_diff_insulin,
  (COALESCE(f12.oral_count, 0) - COALESCE(l72.oral_count, 0)) AS pp_diff_oral
FROM 
  first_12_hours_medication f12
FULL OUTER JOIN 
  last_72_hours_medication l72 
    ON f12.hadm_id = l72.hadm_id;