WITH 
-- Identify heart failure ICD codes
heart_failure_icd AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code LIKE '428%'
),

-- Calculate Charlson comorbidity index
charlson_index AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    COUNT(DISTINCT i.icd_code) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` i ON a.hadm_id = i.hadm_id
  GROUP BY a.subject_id, a.hadm_id
),

-- Prepare patient data
patient_data AS (
  SELECT 
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    a.discharge_location,
    COALESCE(ci.charlson_score, 0) AS charlson_score
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  LEFT JOIN charlson_index ci ON a.subject_id = ci.subject_id AND a.hadm_id = ci.hadm_id
  WHERE p.gender = 'M' 
    AND p.anchor_age BETWEEN 53 AND 63
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` i
      JOIN heart_failure_icd h ON i.icd_code = h.icd_code
      WHERE i.hadm_id = a.hadm_id
    )
)

-- Calculate in-hospital mortality, LOS, and discharge destination
SELECT 
  -- Group by LOS categories and Charlson index
  CASE 
    WHEN DATE_DIFF(a.dischtime, a.admittime, 'DAY') BETWEEN 1 AND 3 THEN '1-3'
    WHEN DATE_DIFF(a.dischtime, a.admittime, 'DAY') BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END AS los_category,
  CASE 
    WHEN a.charlson_score <= 3 THEN '<=3'
    WHEN a.charlson_score BETWEEN 4 AND 5 THEN '4-5'
    ELSE '>5'
  END AS charlson_category,
  -- Calculate in-hospital mortality
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS deaths,
  COUNT(a.hadm_id) AS total_patients,
  -- Calculate discharge destination percentages
  SUM(CASE WHEN LOWER(a.discharge_location) LIKE '%home%' THEN 1 ELSE 0 END) AS discharged_home,
  SUM(CASE WHEN LOWER(a.discharge_location) LIKE '%rehab%' THEN 1 ELSE 0 END) AS discharged_rehab,
  SUM(CASE WHEN LOWER(a.discharge_location) LIKE '%snf%' THEN 1 ELSE 0 END) AS discharged_snf,
  SUM(CASE WHEN LOWER(a.discharge_location) LIKE '%hospice%' THEN 1 ELSE 0 END) AS discharged_hospice
FROM patient_data a
GROUP BY 
  CASE 
    WHEN DATE_DIFF(a.dischtime, a.admittime, 'DAY') BETWEEN 1 AND 3 THEN '1-3'
    WHEN DATE_DIFF(a.dischtime, a.admittime, 'DAY') BETWEEN 4 AND 7 THEN '4-7'
    ELSE '>=8'
  END,
  CASE 
    WHEN a.charlson_score <= 3 THEN '<=3'
    WHEN a.charlson_score BETWEEN 4 AND 5 THEN '4-5'
    ELSE '>5'
  END;