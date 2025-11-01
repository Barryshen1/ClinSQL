WITH 
-- Identify relevant patients
patients_relevant AS (
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
  ON 
    p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M' 
    AND p.anchor_age BETWEEN 36 AND 46
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
        AND icd_version = 'ICD-9'
    )
    AND a.hadm_id IN (
      SELECT 
        hadm_id
      FROM 
        `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        icd_code IN ('402.01', '402.11', '402.21', '402.31', '404.01', '404.11', '404.21', '404.31')
        AND icd_version = 'ICD-9'
    )
),

-- Identify antidiabetic medications
antidiabetics AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    pr.starttime,
    pr.drug,
    CASE 
      WHEN REGEXP_CONTAINS(PR.drug, r'metformin', 'i') THEN 'Metformin'
      WHEN REGEXP_CONTAINS(PR.drug, r'sulfonylurea', 'i') THEN 'Sulfonylurea'
      WHEN REGEXP_CONTAINS(PR.drug, r'thiazolidinedione', 'i') THEN 'Thiazolidinedione'
      WHEN REGEXP_CONTAINS(PR.drug, r'meglitinide', 'i') THEN 'Meglitinide'
      WHEN REGEXP_CONTAINS(PR.drug, r'GLP-1', 'i') THEN 'GLP-1 receptor agonist'
      WHEN REGEXP_CONTAINS(PR.drug, r'DPP-4', 'i') THEN 'DPP-4 inhibitor'
      WHEN REGEXP_CONTAINS(PR.drug, r'SGLT2', 'i') THEN 'SGLT2 inhibitor'
      ELSE 'Other'
    END AS drug_class
  FROM 
    patients_relevant p
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  ON 
    p.hadm_id = pr.hadm_id
  WHERE 
    pr.starttime BETWEEN p.admittime AND p.dischtime
),

-- Calculate time intervals
time_intervals AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AS first_12_hours_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 48 HOUR) AS final_48_hours_start
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions`
)

-- Calculate initiation rates
SELECT 
  drug_class,
  COUNT(CASE WHEN starttime BETWEEN admittime AND first_12_hours_end THEN 1 END) AS first_12_hours_initiations,
  COUNT(CASE WHEN starttime BETWEEN final_48_hours_start AND dischtime THEN 1 END) AS final_48_hours_initiations,
  COUNT(*) AS total_initiations
FROM 
  antidiabetics a
JOIN 
  time_intervals t
ON 
  a.hadm_id = t.hadm_id
GROUP BY 
  drug_class
ORDER BY 
  drug_class;