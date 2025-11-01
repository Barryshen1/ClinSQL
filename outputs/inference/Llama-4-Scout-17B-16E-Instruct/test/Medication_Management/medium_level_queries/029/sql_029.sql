WITH 
-- Patients of interest
patients_of_interest AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    p.anchor_age, 
    p.gender,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 69 AND 79
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code IN ('250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13', 
                      '250.20', '250.21', '250.22', '250.23', '250.30', '250.31', '250.32', '250.33', 
                      '250.40', '250.41', '250.42', '250.43', '250.50', '250.51', '250.52', '250.53', 
                      '250.60', '250.61', '250.62', '250.63', '250.70', '250.71', '250.72', '250.73', 
                      '250.80', '250.81', '250.82', '250.83', '250.90', '250.91', '250.92', '250.93') 
        AND icd_version = 'ICD-9'
    )
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code IN ('402.01', '402.11', '402.21', '404.01', '404.11', '404.21', '404.31', '404.91', 
                      '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9') 
        AND icd_version = 'ICD-9'
    )
),

-- Drug classes of interest
drug_classes AS (
  SELECT 
    poe_id,
    hadm_id,
    subject_id,
    drug,
    charttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  UNION ALL
  SELECT 
    NULL AS poe_id,
    hadm_id,
    subject_id,
    medication AS drug,
    charttime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.emar`
),

-- First 72 hours
first_72_hours AS (
  SELECT 
    subject_id,
    hadm_id,
    drug,
    charttime
  FROM 
    drug_classes
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients_of_interest)
    AND charttime IS NOT NULL
    AND charttime BETWEEN 
      (SELECT 
         admittime 
       FROM 
         patients_of_interest 
       WHERE 
         patients_of_interest.hadm_id = drug_classes.hadm_id) 
      AND 
      TIMESTAMP_ADD(
        (SELECT 
           admittime 
         FROM 
           patients_of_interest 
         WHERE 
           patients_of_interest.hadm_id = drug_classes.hadm_id), 
        INTERVAL 3 DAY
      )
),

-- Last 72 hours
last_72_hours AS (
  SELECT 
    subject_id,
    hadm_id,
    drug,
    charttime
  FROM 
    drug_classes
  WHERE 
    hadm_id IN (SELECT hadm_id FROM patients_of_interest)
    AND charttime IS NOT NULL
    AND charttime BETWEEN 
      TIMESTAMP_SUB(
        (SELECT 
           dischtime 
         FROM 
           patients_of_interest 
         WHERE 
           patients_of_interest.hadm_id = drug_classes.hadm_id), 
        INTERVAL 3 DAY
      ) 
      AND 
      (SELECT 
         dischtime 
       FROM 
         patients_of_interest 
       WHERE 
         patients_of_interest.hadm_id = drug_classes.hadm_id)
),

-- Identify drug classes
identified_drugs AS (
  SELECT 
    subject_id,
    hadm_id,
    drug,
    CASE 
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%dpp-4%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%sglt2%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%glp-1%' THEN 'GLP-1'
      WHEN LOWER(drug) LIKE '%tzd%' THEN 'TZD'
      ELSE 'Other'
    END AS drug_class
  FROM 
    first_72_hours
  UNION ALL
  SELECT 
    subject_id,
    hadm_id,
    drug,
    CASE 
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%dpp-4%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%sglt2%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%glp-1%' THEN 'GLP-1'
      WHEN LOWER(drug) LIKE '%tzd%' THEN 'TZD'
      ELSE 'Other'
    END AS drug_class
  FROM 
    last_72_hours
)

-- Calculate percentage of patients receiving each drug class
SELECT 
  drug_class,
  COUNT(DISTINCT subject_id) AS patients_receiving_drug,
  (SELECT 
     COUNT(DISTINCT subject_id) 
   FROM 
     patients_of_interest) AS total_patients,
  ROUND(COUNT(DISTINCT subject_id) / 
          (SELECT 
             COUNT(DISTINCT subject_id) 
           FROM 
             patients_of_interest) * 100, 2) AS percentage
FROM 
  identified_drugs
WHERE 
  drug_class NOT IN ('Other')
GROUP BY 
  drug_class;