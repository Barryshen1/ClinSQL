WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1
    ON p.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd1
    ON d1.icd_code = dicd1.icd_code AND d1.icd_version = dicd1.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
    ON p.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd2
    ON d2.icd_code = dicd2.icd_code AND d2.icd_version = dicd2.icd_version
  WHERE p.anchor_age BETWEEN 71 AND 81
    AND p.gender = 'M'
    AND LOWER(dicd1.long_title) LIKE '%diabetes%'
    AND LOWER(dicd2.long_title) LIKE '%heart failure%'
    AND LOWER(dicd2.long_title) LIKE '%acute%'
),

prescriptions_filtered AS (
  SELECT p.subject_id, p.drug, p.starttime, c.admittime, c.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c
    ON p.subject_id = c.subject_id
  WHERE p.starttime >= c.admittime
    AND p.starttime <= c.dischtime
),

drug_classes AS (
  SELECT subject_id, starttime, admittime, dischtime,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%gliclazide%' 
           OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%chlorpropamide%' OR LOWER(drug) LIKE '%tolbutamide%'
           OR LOWER(drug) LIKE '%tolazamide%' THEN 'sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%'
           OR LOWER(drug) LIKE '%alogliptin%' OR LOWER(drug) LIKE '%vildagliptin%' THEN 'dpp4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%'
           OR LOWER(drug) LIKE '%ertugliflozin%' THEN 'sglt2'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'thiazolidinediones'
      ELSE NULL
    END AS drug_class
  FROM prescriptions_filtered
  WHERE LOWER(drug) LIKE '%metformin%'
     OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%gliclazide%' 
     OR LOWER(drug) LIKE '%glimepiride%' OR LOWER(drug) LIKE '%chlorpropamide%' OR LOWER(drug) LIKE '%tolbutamide%'
     OR LOWER(drug) LIKE '%tolazamide%'
     OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%'
     OR LOWER(drug) LIKE '%alogliptin%' OR LOWER(drug) LIKE '%vildagliptin%'
     OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%'
     OR LOWER(drug) LIKE '%ertugliflozin%'
     OR LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%'
)

SELECT 
  drug_class,
  COUNTIF(starttime BETWEEN admittime AND admittime + INTERVAL 72 HOUR) * 100.0 / COUNT(*) AS initiation_rate_first_72h,
  COUNTIF(starttime BETWEEN dischtime - INTERVAL 48 HOUR AND dischtime) * 100.0 / COUNT(*) AS initiation_rate_last_48h
FROM drug_classes
WHERE drug_class IS NOT NULL
GROUP BY drug_class
ORDER BY drug_class;