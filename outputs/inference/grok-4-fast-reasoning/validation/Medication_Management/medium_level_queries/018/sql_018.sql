WITH t2dm_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'E11%')
     OR (icd_version = 9 AND icd_code LIKE '250.%' AND icd_code NOT LIKE '250.1%')
),
hf_hadms AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
     OR (icd_version = 9 AND icd_code LIKE '428%')
),
cohort AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE a.hadm_id IN (SELECT hadm_id FROM t2dm_hadms)
    AND a.hadm_id IN (SELECT hadm_id FROM hf_hadms)
    AND p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),
total_adms AS (
  SELECT COUNT(*) AS total_adm
  FROM cohort
),
classes_list AS (
  SELECT 'Metformin' AS med_class UNION ALL
  SELECT 'Sulfonylurea' UNION ALL
  SELECT 'DPP4' UNION ALL
  SELECT 'SGLT2' UNION ALL
  SELECT 'TZD'
),
all_pres AS (
  SELECT 
    c.hadm_id, 
    c.admittime, 
    c.dischtime, 
    p.starttime, 
    COALESCE(p.stoptime, c.dischtime) AS effective_end,
    LOWER(p.drug) AS drug_lower
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON c.hadm_id = p.hadm_id
  WHERE p.route = 'PO'
    AND p.drug IS NOT NULL
),
classes AS (
  SELECT 
    hadm_id, 
    admittime, 
    dischtime, 
    starttime, 
    effective_end,
    CASE
      WHEN drug_lower LIKE '%metformin%' THEN 'Metformin'
      WHEN drug_lower LIKE '%glimepiride%' OR drug_lower LIKE '%glipizide%' OR drug_lower LIKE '%glyburide%' 
        OR drug_lower LIKE '%tolbutamide%' OR drug_lower LIKE '%chlorpropamide%' OR drug_lower LIKE '%tolazamide%' THEN 'Sulfonylurea'
      WHEN drug_lower LIKE '%sitagliptin%' OR drug_lower LIKE '%saxagliptin%' OR drug_lower LIKE '%linagliptin%' 
        OR drug_lower LIKE '%alogliptin%' OR drug_lower LIKE '%vildagliptin%' THEN 'DPP4'
      WHEN drug_lower LIKE '%canagliflozin%' OR drug_lower LIKE '%dapagliflozin%' OR drug_lower LIKE '%empagliflozin%' 
        OR drug_lower LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN drug_lower LIKE '%pioglitazone%' OR drug_lower LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS med_class
  FROM all_pres
  WHERE CASE
      WHEN drug_lower LIKE '%metformin%' THEN 'Metformin'
      WHEN drug_lower LIKE '%glimepiride%' OR drug_lower LIKE '%glipizide%' OR drug_lower LIKE '%glyburide%' 
        OR drug_lower LIKE '%tolbutamide%' OR drug_lower LIKE '%chlorpropamide%' OR drug_lower LIKE '%tolazamide%' THEN 'Sulfonylurea'
      WHEN drug_lower LIKE '%sitagliptin%' OR drug_lower LIKE '%saxagliptin%' OR drug_lower LIKE '%linagliptin%' 
        OR drug_lower LIKE '%alogliptin%' OR drug_lower LIKE '%vildagliptin%' THEN 'DPP4'
      WHEN drug_lower LIKE '%canagliflozin%' OR drug_lower LIKE '%dapagliflozin%' OR drug_lower LIKE '%empagliflozin%' 
        OR drug_lower LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN drug_lower LIKE '%pioglitazone%' OR drug_lower LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END IS NOT NULL
),
first72_usage AS (
  SELECT DISTINCT hadm_id, med_class
  FROM classes
  WHERE starttime < DATETIME_ADD(admittime, INTERVAL 72 HOUR)
    AND effective_end > admittime
),
final48_usage AS (
  SELECT DISTINCT hadm_id, med_class
  FROM classes
  WHERE starttime < dischtime
    AND effective_end > DATETIME_ADD(dischtime, INTERVAL -48 HOUR)
),
first_counts AS (
  SELECT med_class, COUNT(DISTINCT hadm_id) AS n_first
  FROM first72_usage
  GROUP BY med_class
),
final_counts AS (
  SELECT med_class, COUNT(DISTINCT hadm_id) AS n_final
  FROM final48_usage
  GROUP BY med_class
)
SELECT 
  cl.med_class,
  ROUND(COALESCE(fc.n_first, 0) * 100.0 / ta.total_adm, 2) AS prev_first_pct,
  ROUND(COALESCE(fn.n_final, 0) * 100.0 / ta.total_adm, 2) AS prev_final_pct,
  ROUND(ABS(COALESCE(fn.n_final, 0) - COALESCE(fc.n_first, 0)) * 100.0 / ta.total_adm, 2) AS abs_pp_diff
FROM classes_list cl
LEFT JOIN first_counts fc ON cl.med_class = fc.med_class
LEFT JOIN final_counts fn ON cl.med_class = fn.med_class
CROSS JOIN total_adms ta
ORDER BY cl.med_class;