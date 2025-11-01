WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    p.anchor_age,
    p.gender,
    a.dischtime,
    a.hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.anchor_age BETWEEN 84 AND 94
    AND p.gender = 'F'
    AND a.admittime <= TIMESTAMP_ADD(a.admittime, INTERVAL 48 HOUR)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
      AND d.icd_code LIKE '250.1%'  -- DKA ICD-9 code
    )
),

-- Identify hyperkalemia-risk drug interactions
hyperkalemia_risk_drugs AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS num_drugs
  FROM 
    patients_of_interest p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
  WHERE 
    LOWER(pr.drug) IN ('potassium', 'ace inhibitors', 'arbs', 'aldosterone antagonists', 'trimethoprim')  
  GROUP BY 
    p.hadm_id
),

-- Calculate medication complexity and outcomes
patient_data AS (
  SELECT 
    p.hadm_id,
    COUNT(DISTINCT pr.drug) AS medication_complexity,
    DATE_DIFF(p.dischtime, p.admittime) AS los,
    p.hospital_expire_flag AS mortality,
    COALESCE(h.num_drugs, 0) AS num_hyperkalemia_risk_drugs
  FROM 
    patients_of_interest p
  LEFT JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
  LEFT JOIN 
    hyperkalemia_risk_drugs h ON p.hadm_id = h.hadm_id
  GROUP BY 
    p.hadm_id, p.dischtime, p.hospital_expire_flag, h.num_drugs, p.admittime
)

-- Final analysis
SELECT 
  CASE 
    WHEN num_hyperkalemia_risk_drugs > 0 THEN 'With hyperkalemia-risk drug interactions'
    ELSE 'Without hyperkalemia-risk drug interactions'
  END AS group_name,
  AVG(medication_complexity) AS mean_medication_complexity,
  PERCENTILE_CONT(0.5)(medication_complexity) OVER (PARTITION BY 
    CASE 
      WHEN num_hyperkalemia_risk_drugs > 0 THEN 'With hyperkalemia-risk drug interactions'
      ELSE 'Without hyperkalemia-risk drug interactions'
    END) AS median_medication_complexity,
  AVG(los) AS mean_los,
  SUM(mortality) / COUNT(hadm_id) AS mortality_rate
FROM 
  patient_data
GROUP BY 
  1, num_hyperkalemia_risk_drugs;