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
    AND p.anchor_age BETWEEN 63 AND 73
),

-- Identify patients with T2DM and HF
patients_with_conditions AS (
  SELECT 
    subject_id, 
    hadm_id
  FROM 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    icd_code IN (
      -- T2DM
      '250.00', '250.01', '250.02', '250.03', '250.04', '250.05', '250.06', '250.07', '250.08', '250.09',
      '250.10', '250.11', '250.12', '250.13', '250.14', '250.15', '250.16', '250.17', '250.18', '250.19',
      '250.20', '250.21', '250.22', '250.23', '250.24', '250.25', '250.26', '250.27', '250.28', '250.29',
      '250.30', '250.31', '250.32', '250.33', '250.34', '250.35', '250.36', '250.37', '250.38', '250.39',
      '250.40', '250.41', '250.42', '250.43', '250.44', '250.45', '250.46', '250.47', '250.48', '250.49',
      '250.50', '250.51', '250.52', '250.53', '250.54', '250.55', '250.56', '250.57', '250.58', '250.59',
      '250.60', '250.61', '250.62', '250.63', '250.64', '250.65', '250.66', '250.67', '250.68', '250.69',
      '250.70', '250.71', '250.72', '250.73', '250.74', '250.75', '250.76', '250.77', '250.78', '250.79',
      '250.80', '250.81', '250.82', '250.83', '250.84', '250.85', '250.86', '250.87', '250.88', '250.89',
      '250.90', '250.91', '250.92', '250.93', '250.94', '250.95', '250.96', '250.97', '250.98', '250.99',
      -- HF
      '428.0', '428.1', '428.2', '428.3', '428.4', '428.5', '428.6', '428.7', '428.8', '428.9', '428.30', 
      '428.31', '428.32', '428.33', '428.34', '428.35', '428.36', '428.37', '428.38', '428.39'
    )
),

-- Identify medication usage in first and last 24h
medication_usage AS (
  SELECT 
    p.subject_id, 
    p.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug,
    CASE 
      WHEN pr.starttime BETWEEN TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY) AND TIMESTAMP_ADD(a.admittime, INTERVAL 2 DAY) THEN 'first_24h'
      WHEN pr.stoptime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 1 DAY) AND a.dischtime THEN 'last_24h'
    END AS period,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) NOT LIKE '%insulin%' 
        AND (LOWER(pr.drug) LIKE '%oral%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%sulfonylurea%') THEN 'Oral Agents'
    END AS medication_type
  FROM 
    patients_of_interest p
  JOIN 
    patients_with_conditions c 
      ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.hadm_id = a.hadm_id
  WHERE 
    pr.drug_type = 'medication'
    AND (LOWER(pr.drug) LIKE '%insulin%' 
      OR LOWER(pr.drug) NOT LIKE '%insulin%' 
        AND (LOWER(pr.drug) LIKE '%oral%' OR LOWER(pr.drug) LIKE '%metformin%' OR LOWER(pr.drug) LIKE '%sulfonylurea%'))
)

SELECT 
  medication_type AS medication,
  COALESCE(COUNT(DISTINCT CASE WHEN period = 'first_24h' THEN hadm_id END) / 
    COUNT(DISTINCT hadm_id) * 100, 0) AS first_24h_prevalence,
  COALESCE(COUNT(DISTINCT CASE WHEN period = 'last_24h' THEN hadm_id END) / 
    COUNT(DISTINCT hadm_id) * 100, 0) AS last_24h_prevalence,
  COALESCE(COUNT(DISTINCT CASE WHEN period = 'last_24h' THEN hadm_id END) / 
    COUNT(DISTINCT hadm_id) * 100 - COUNT(DISTINCT CASE WHEN period = 'first_24h' THEN hadm_id END) / 
    COUNT(DISTINCT hadm_id) * 100, 0) AS net_change_pp
FROM 
  medication_usage
GROUP BY 
  medication;