WITH patient_population AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 42 AND 52
    AND p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(d_icd.long_title) LIKE '%diabetes%'
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd 
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE d.hadm_id = a.hadm_id
        AND LOWER(d_icd.long_title) LIKE '%heart failure%'
        AND LOWER(d_icd.long_title) LIKE '%acute%'
    )
),
prescriptions_with_class AS (
  SELECT
    p.hadm_id,
    p.admittime,
    p.dischtime,
    pr.drug,
    pr.starttime,
    CASE
      WHEN LOWER(pr.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glibenclamide%' THEN 'Sulfonylurea'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' THEN 'SGLT2'
      WHEN LOWER(pr.drug) LIKE '%liraglutide%' OR LOWER(pr.drug) LIKE '%exenatide%' OR LOWER(pr.drug) LIKE '%semaglutide%' THEN 'GLP-1'
      WHEN LOWER(pr.drug) LIKE '%pioglitazone%' OR LOWER(pr.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM patient_population p
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
),
class_presence AS (
  SELECT
    hadm_id,
    drug_class,
    MAX(CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL '24' HOUR THEN 1 ELSE 0 END) AS first_24h,
    MAX(CASE WHEN starttime BETWEEN dischtime - INTERVAL '12' HOUR AND dischtime THEN 1 ELSE 0 END) AS last_12h
  FROM prescriptions_with_class
  GROUP BY hadm_id, drug_class
),
classes AS (
  SELECT 'Insulin' AS drug_class UNION ALL
  SELECT 'Metformin' UNION ALL
  SELECT 'Sulfonylurea' UNION ALL
  SELECT 'DPP-4' UNION ALL
  SELECT 'SGLT2' UNION ALL
  SELECT 'GLP-1' UNION ALL
  SELECT 'TZD'
),
total_patients AS (
  SELECT COUNT(DISTINCT hadm_id) AS total FROM patient_population
)
SELECT
  c.drug_class,
  ROUND(100.0 * COALESCE(SUM(cp.first_24h), 0) / tp.total, 2) AS first_24h_prevalence,
  ROUND(100.0 * COALESCE(SUM(cp.last_12h), 0) / tp.total, 2) AS last_12h_prevalence,
  ROUND(100.0 * (COALESCE(SUM(cp.last_12h), 0) - COALESCE(SUM(cp.first_24h), 0)) / tp.total, 2) AS net_change
FROM classes c
LEFT JOIN class_presence cp ON c.drug_class = cp.drug_class
CROSS JOIN total_patients tp
GROUP BY c.drug_class, tp.total
ORDER BY c.drug_class;