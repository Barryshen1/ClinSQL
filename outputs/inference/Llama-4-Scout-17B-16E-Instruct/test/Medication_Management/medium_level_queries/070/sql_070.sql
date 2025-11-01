WITH 
-- Filter target population
target_population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON 
    a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    -- Assuming T2DM and HF can be identified via ICD codes in diagnoses_icd
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code IN ('250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13', '428.0', '428.1', '428.2', '428.3', '428.4', '428.8', '428.9')
    )
),

-- Medication administration within time frames
medication_administration AS (
  SELECT 
    tp.subject_id,
    tp.hadm_id,
    tp.admittime,
    tp.dischtime,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%sulfonylurea%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(p.drug) LIKE '%dpp-4%' OR LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
      WHEN LOWER(p.drug) LIKE '%sglt2%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitors'
      ELSE 'Other'
    END AS medication_class
  FROM 
    target_population tp
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  ON 
    tp.hadm_id = p.hadm_id
)

-- Calculate prevalence in first 48h and last 12h
SELECT 
  ma.medication_class,
  COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(ma.starttime, ma.admittime, HOUR) BETWEEN 0 AND 48 THEN ma.hadm_id END) / COUNT(DISTINCT ma.hadm_id) * 100 AS prevalence_first_48h,
  COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(ma.dischtime, ma.starttime, HOUR) BETWEEN 0 AND 12 THEN ma.hadm_id END) / COUNT(DISTINCT ma.hadm_id) * 100 AS prevalence_last_12h,
  COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(ma.starttime, ma.admittime, HOUR) BETWEEN 0 AND 48 THEN ma.hadm_id END) / COUNT(DISTINCT ma.hadm_id) * 100 
  - COUNT(DISTINCT CASE WHEN TIMESTAMP_DIFF(ma.dischtime, ma.starttime, HOUR) BETWEEN 0 AND 12 THEN ma.hadm_id END) / COUNT(DISTINCT ma.hadm_id) * 100 
  AS net_percentage_point_change
FROM 
  medication_administration ma
GROUP BY 
  ma.medication_class
HAVING 
  ma.medication_class != 'Other';