WITH 
-- Patient selection
patients_hhs AS (
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
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      ON a.hadm_id = d.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 68 AND 78
    AND dd.long_title LIKE '%Hyperglycemic Hyperosmolar Syndrome%'
),

-- Medication complexity
medication_complexity AS (
  SELECT 
    subject_id, 
    hadm_id, 
    COUNT(DISTINCT drug) AS num_drugs
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY 
    subject_id, 
    hadm_id
),

-- Hyperkalemia-risk drug interactions
hyperkalemia_risk AS (
  SELECT 
    p.subject_id, 
    p.hadm_id
  FROM 
    patients_hhs p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
  WHERE 
    -- Identify hyperkalemia-risk drugs
    pr.drug LIKE '%potassium%'
    OR pr.drug LIKE '%hyperkalemia%'
),

-- LOS and Mortality
los_mortality AS (
  SELECT 
    subject_id, 
    hadm_id, 
    TIMESTAMPDIFF(DAY, admittime, dischtime) AS los,
    hospital_expire_flag
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
),

-- Calculations
medication_complexity_distribution AS (
  SELECT 
    PERCENTILE_CONT(0.5)(num_drugs) AS median_medication_complexity
  FROM 
    medication_complexity
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients_hhs)
),

hyperkalemia_risk_percent AS (
  SELECT 
    COUNT(DISTINCT hr.hadm_id) / COUNT(DISTINCT p.hadm_id) AS percent_hyperkalemia_risk
  FROM 
    patients_hhs p
  LEFT JOIN 
    hyperkalemia_risk hr ON p.hadm_id = hr.hadm_id
),

los_top_quartile AS (
  SELECT 
    PERCENTILE_CONT(0.75)(los) AS top_quartile_los
  FROM 
    los_mortality
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients_hhs)
),

mortality_rate_calc AS (
  SELECT 
    SUM(hospital_expire_flag) / COUNT(hadm_id) AS mortality_rate
  FROM 
    los_mortality
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients_hhs)
)

-- Final calculations
SELECT 
  (SELECT median_medication_complexity FROM medication_complexity_distribution),
  (SELECT percent_hyperkalemia_risk FROM hyperkalemia_risk_percent),
  (SELECT top_quartile_los FROM los_top_quartile),
  (SELECT mortality_rate FROM mortality_rate_calc);