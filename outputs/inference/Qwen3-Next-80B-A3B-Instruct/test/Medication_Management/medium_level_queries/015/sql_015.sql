WITH diabetes_hf_patients AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1_long ON d1.icd_code = d1_long.icd_code AND d1.icd_version = d1_long.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2_long ON d2.icd_code = d2_long.icd_code AND d2.icd_version = d2_long.icd_version
  WHERE p.anchor_age BETWEEN 42 AND 52
    AND p.gender = 'M'
    AND (
      (d1_long.long_title LIKE '%diabetes%' AND d1.icd_code LIKE 'E1%')
      OR d1.icd_code IN ('250.0', '250.1', '250.2', '250.3', '250.4', '250.5', '250.6', '250.7', '250.8', '250.9')
    )
    AND (
      d2_long.long_title LIKE '%heart failure%' AND d2.icd_code LIKE 'I50%'
    )
),
prescriptions_in_window AS (
  SELECT
    d.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%gliclazide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%dulaglutide%' THEN 'GLP-1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN diabetes_hf_patients d ON p.hadm_id = d.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.drug IS NOT NULL
),
first_24h AS (
  SELECT
    drug_class,
    COUNT(*) AS count_first_24h,
    COUNT(*) * 100.0 / COUNT(*) OVER () AS pct_first_24h
  FROM prescriptions_in_window
  WHERE starttime >= admittime AND starttime <= admittime + INTERVAL 24 HOUR
  GROUP BY drug_class
),
last_12h AS (
  SELECT
    drug_class,
    COUNT(*) AS count_last_12h,
    COUNT(*) * 100.0 / COUNT(*) OVER () AS pct_last_12h
  FROM prescriptions_in_window
  WHERE stoptime >= dischtime - INTERVAL 12 HOUR AND stoptime <= dischtime
  GROUP BY drug_class
),
all_classes AS (
  SELECT DISTINCT drug_class FROM prescriptions_in_window WHERE drug_class IS NOT NULL
)
SELECT
  ac.drug_class,
  COALESCE(f.pct_first_24h, 0) AS pct_first_24h,
  COALESCE(l.pct_last_12h, 0) AS pct_last_12h,
  COALESCE(l.pct_last_12h, 0) - COALESCE(f.pct_first_24h, 0) AS net_change_pp
FROM all_classes ac
LEFT JOIN first_24h f ON ac.drug_class = f.drug_class
LEFT JOIN last_12h l ON ac.drug_class = l.drug_class
ORDER BY ac.drug_class;