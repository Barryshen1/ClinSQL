WITH patient_admissions AS (
  SELECT DISTINCT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
),
t2dm_hf_admissions AS (
  SELECT pa.hadm_id, pa.admittime, pa.dischtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di1 ON pa.hadm_id = di1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d1 ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di2 ON pa.hadm_id = di2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d2 ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE (d1.icd_code LIKE 'E11%' AND d1.icd_version = 10)
    AND (d2.icd_code LIKE 'I50%' AND d2.icd_version = 10)
),
drug_exposure AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'met'
      WHEN LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glimipiride%' OR LOWER(p.drug) LIKE '%chlorpropamide%' OR LOWER(p.drug) LIKE '%tolazamide%' OR LOWER(p.drug) LIKE '%acetohexamide%' OR LOWER(p.drug) LIKE '%tolbutamide%' OR LOWER(p.drug) LIKE '%diabeta%' OR LOWER(p.drug) LIKE '%glucotrol%' THEN 'SU'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%lixisenatide%' THEN 'GLP-1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM t2dm_hf_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p ON a.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.drug IS NOT NULL
),
windowed_initiation AS (
  SELECT 
    hadm_id,
    drug_class,
    CASE WHEN starttime <= DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END AS in_first_12h,
    CASE WHEN starttime >= DATETIME_SUB(dischtime, INTERVAL 48 HOUR) THEN 1 ELSE 0 END AS in_final_48h
  FROM drug_exposure
  WHERE drug_class IS NOT NULL
),
class_summary AS (
  SELECT 
    drug_class,
    AVG(CAST(in_first_12h AS FLOAT64)) * 100 AS first_12h_pct,
    AVG(CAST(in_final_48h AS FLOAT64)) * 100 AS final_48h_pct
  FROM windowed_initiation
  GROUP BY drug_class
)
SELECT 
  drug_class,
  ROUND(first_12h_pct, 2) AS first_12h_pct,
  ROUND(final_48h_pct, 2) AS final_48h_pct,
  ROUND(final_48h_pct - first_12h_pct, 2) AS net_change_pp
FROM class_summary
ORDER BY drug_class;