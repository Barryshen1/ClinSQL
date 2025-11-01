WITH 
-- Identify target patients
target_patients AS (
  SELECT p.subject_id, p.anchor_age, p.gender, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 36 AND 46
  AND (d.icd_code LIKE '%250%' OR d.icd_code LIKE '%402%')  -- Diabetes and heart failure
),

-- Extract medication orders for target patients
medication_orders AS (
  SELECT 
    tp.subject_id, 
    tp.hadm_id, 
    tp.admittime, 
    tp.dischtime, 
    CASE 
      WHEN p.drug LIKE '%insulin%' OR p.drug LIKE '%metformin%' THEN 'antidiabetic'
      WHEN p.drug LIKE '%beta-blocker%' OR p.drug LIKE '%ACE inhibitor%' THEN 'cardiac'
    END AS drug_class,
    p.drug, 
    p.starttime
  FROM target_patients tp
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON tp.hadm_id = p.hadm_id
)

-- Calculate prevalence in first 48 hours and last 12 hours
SELECT 
  drug_class,
  COUNT(CASE WHEN starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 48 HOUR) THEN 1 END) AS first_48h_count,
  COUNT(CASE WHEN starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) AND dischtime THEN 1 END) AS last_12h_count,
  COUNT(*) AS total_count
FROM medication_orders
GROUP BY drug_class;