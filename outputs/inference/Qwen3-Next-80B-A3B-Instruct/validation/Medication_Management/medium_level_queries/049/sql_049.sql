WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM 
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN 
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 66 AND 76
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
diabetes_hf AS (
  SELECT DISTINCT
    c.subject_id,
    c.hadm_id
  FROM 
    cohort c
  JOIN 
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON c.hadm_id = d.hadm_id
  JOIN 
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE 
    (dicd.icd_code LIKE 'E10%' OR dicd.icd_code LIKE 'E11%' OR dicd.icd_code LIKE 'E12%' OR dicd.icd_code LIKE 'E13%' OR dicd.icd_code LIKE 'E14%') -- diabetes
    OR dicd.long_title LIKE '%heart failure%' OR dicd.long_title LIKE '%congestive heart failure%'
),
prescriptions_filtered AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    p.drug,
    p.dose_val_rx,
    p.dose_unit_rx
  FROM 
    physionet-data.mimiciv_3_1_hosp.prescriptions p
  INNER JOIN 
    diabetes_hf dh
    ON p.hadm_id = dh.hadm_id
  WHERE 
    p.starttime IS NOT NULL
    AND p.drug IS NOT NULL
),
antidiabetic_classes AS (
  SELECT 
    pf.hadm_id,
    pf.starttime,
    CASE 
      WHEN LOWER(pf.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pf.drug) LIKE '%sulfonylurea%' OR LOWER(pf.drug) LIKE '%glipizide%' OR LOWER(pf.drug) LIKE '%glyburide%' OR LOWER(pf.drug) LIKE '%gliclazide%' THEN 'Sulfonylurea'
      WHEN LOWER(pf.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(pf.drug) LIKE '%dpp-4%' OR LOWER(pf.drug) LIKE '%sitagliptin%' OR LOWER(pf.drug) LIKE '%saxagliptin%' OR LOWER(pf.drug) LIKE '%linagliptin%' OR LOWER(pf.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitor'
      WHEN LOWER(pf.drug) LIKE '%glp-1%' OR LOWER(pf.drug) LIKE '%exenatide%' OR LOWER(pf.drug) LIKE '%liraglutide%' OR LOWER(pf.drug) LIKE '%semaglutide%' OR LOWER(pf.drug) LIKE '%dulaglutide%' THEN 'GLP-1 RA'
      WHEN LOWER(pf.drug) LIKE '%sglt2%' OR LOWER(pf.drug) LIKE '%empagliflozin%' OR LOWER(pf.drug) LIKE '%canagliflozin%' OR LOWER(pf.drug) LIKE '%dapagliflozin%' THEN 'SGLT2 Inhibitor'
      WHEN LOWER(pf.drug) LIKE '%thiazolidinedione%' OR LOWER(pf.drug) LIKE '%pioglitazone%' OR LOWER(pf.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
      WHEN LOWER(pf.drug) LIKE '%meglitinide%' OR LOWER(pf.drug) LIKE '%repaglinide%' OR LOWER(pf.drug) LIKE '%nateglinide%' THEN 'Meglitinide'
      ELSE 'Other'
    END AS antidiabetic_class
  FROM 
    prescriptions_filtered pf
),
first_72h AS (
  SELECT 
    antidiabetic_class,
    COUNT(*) AS count
  FROM 
    antidiabetic_classes
  WHERE 
    starttime BETWEEN admittime AND TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR)
  GROUP BY 
    antidiabetic_class
),
final_24h AS (
  SELECT 
    antidiabetic_class,
    COUNT(*) AS count
  FROM 
    antidiabetic_classes
  WHERE 
    starttime BETWEEN TIMESTAMP_SUB(dischtime, INTERVAL 24 HOUR) AND dischtime
  GROUP BY 
    antidiabetic_class
),
total_first_72h AS (
  SELECT SUM(count) AS total FROM first_72h
),
total_final_24h AS (
  SELECT SUM(count) AS total FROM final_24h
)
SELECT 
  'First 72h' AS period,
  f.antidiabetic_class,
  ROUND(100.0 * f.count / t.total, 2) AS percentage
FROM 
  first_72h f
CROSS JOIN 
  total_first_72h t
WHERE 
  f.antidiabetic_class != 'Other'
UNION ALL
SELECT 
  'Final 24h' AS period,
  f.antidiabetic_class,
  ROUND(100.0 * f.count / t.total, 2) AS percentage
FROM 
  final_24h f
CROSS JOIN 
  total_final_24h t
WHERE 
  f.antidiabetic_class != 'Other'
ORDER BY 
  period, percentage DESC;