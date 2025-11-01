WITH 
-- Identify patients of interest
patients_of_interest AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.gender,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a 
      ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code IN (
          '250.00', '250.01', '250.02', '250.03', '250.10', '250.11', '250.12', '250.13', 
          '250.20', '250.21', '250.22', '250.23', '250.30', '250.31', '250.32', '250.33', 
          '250.40', '250.41', '250.42', '250.43', '250.50', '250.51', '250.52', '250.53', 
          '250.60', '250.61', '250.62', '250.63', '250.70', '250.71', '250.72', '250.73', 
          '250.80', '250.81', '250.82', '250.83', '250.90', '250.91', '250.92', '250.93'
        ) 
        AND icd_version = 9
    )
    AND a.hadm_id IN (
      SELECT 
        hadm_id 
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        icd_code = '428.0'
        AND icd_version = 9
    )
),

-- Medication classes
medication_classes AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    pr.starttime,
    pr.stoptime,
    pr.drug
  FROM 
    patients_of_interest p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
      ON p.hadm_id = pr.hadm_id
  WHERE 
    LOWER(pr.drug) LIKE '%antidiabetic%' 
    OR LOWER(pr.drug) LIKE '%beta-blocker%' 
    OR LOWER(pr.drug) LIKE '%acei%' 
    OR LOWER(pr.drug) LIKE '%arb%' 
    OR LOWER(pr.drug) LIKE '%arni%' 
    OR LOWER(pr.drug) LIKE '%loop diuretic%'
),

-- First 24h and last 48h flags
time_periods AS (
  SELECT 
    m.subject_id,
    m.hadm_id,
    m.starttime,
    m.stoptime,
    m.drug,
    CASE 
      WHEN m.starttime BETWEEN p.admittime AND TIMESTAMP_ADD(p.admittime, INTERVAL 24 HOUR) THEN 'first_24h'
      ELSE NULL
    END AS in_first_24h,
    CASE 
      WHEN m.stoptime BETWEEN TIMESTAMP_SUB(p.dischtime, INTERVAL 48 HOUR) AND p.dischtime THEN 'last_48h'
      ELSE NULL
    END AS in_last_48h
  FROM 
    medication_classes m
  JOIN 
    patients_of_interest p 
      ON m.subject_id = p.subject_id AND m.hadm_id = p.hadm_id
)

-- Final counts, re-organized for clarity and correctness
SELECT 
  drug,
  COUNT(CASE WHEN in_first_24h IS NOT NULL THEN 1 END) AS count_first_24h,
  COUNT(CASE WHEN in_last_48h IS NOT NULL THEN 1 END) AS count_last_48h
FROM 
  time_periods
GROUP BY 
  drug;