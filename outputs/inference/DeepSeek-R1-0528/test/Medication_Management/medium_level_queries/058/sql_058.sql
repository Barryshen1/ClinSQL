WITH classes AS (
  SELECT 'Biguanides' AS drug_class UNION ALL
  SELECT 'Sulfonylureas' UNION ALL
  SELECT 'Thiazolidinediones' UNION ALL
  SELECT 'DPP-4 inhibitors' UNION ALL
  SELECT 'GLP-1 receptor agonists' UNION ALL
  SELECT 'SGLT2 inhibitors' UNION ALL
  SELECT 'Insulin'
),
cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) + p.anchor_age AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
t2dm AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^250(.*[02])$')) OR
    (icd_version = 10 AND icd_code LIKE 'E11%')
),
hf AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE
    (icd_version = 9 AND icd_code LIKE '428%') OR
    (icd_version = 10 AND icd_code LIKE 'I50%')
),
cohort_conditions AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN t2dm ON c.hadm_id = t2dm.hadm_id
  INNER JOIN hf ON c.hadm_id = hf.hadm_id
  WHERE c.age_at_admission BETWEEN 36 AND 46
),
antidiabetic_prescriptions AS (
  SELECT
    p.hadm_id,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanides'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR 
           LOWER(p.drug) LIKE '%glyburide%' OR 
           LOWER(p.drug) LIKE '%glimepiride%' OR 
           LOWER(p.drug) LIKE '%gliclazide%' THEN 'Sulfonylureas'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR 
           LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR 
           LOWER(p.drug) LIKE '%saxagliptin%' OR 
           LOWER(p.drug) LIKE '%linagliptin%' OR 
           LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
      WHEN LOWER(p.drug) LIKE '%exenatide%' OR 
           LOWER(p.drug) LIKE '%liraglutide%' OR 
           LOWER(p.drug) LIKE '%dulaglutide%' OR 
           LOWER(p.drug) LIKE '%lixisenatide%' OR 
           LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1 receptor agonists'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR 
           LOWER(p.drug) LIKE '%dapagliflozin%' OR 
           LOWER(p.drug) LIKE '%empagliflozin%' OR 
           LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitors'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort_conditions c ON p.hadm_id = c.hadm_id
),
base AS (
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    cl.drug_class
  FROM cohort_conditions c
  CROSS JOIN classes cl
),
first_12h AS (
  SELECT
    p.hadm_id,
    p.drug_class,
    1 AS flag_first_12h
  FROM antidiabetic_prescriptions p
  INNER JOIN cohort_conditions c ON p.hadm_id = c.hadm_id
  WHERE
    p.drug_class IS NOT NULL
    AND p.starttime BETWEEN c.admittime AND 
        DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
  GROUP BY p.hadm_id, p.drug_class
),
final_48h AS (
  SELECT
    p.hadm_id,
    p.drug_class,
    1 AS flag_final_48h
  FROM antidiabetic_prescriptions p
  INNER JOIN cohort_conditions c ON p.hadm_id = c.hadm_id
  WHERE
    p.drug_class IS NOT NULL
    AND p.starttime BETWEEN 
        DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  GROUP BY p.hadm_id, p.drug_class
)
SELECT
  base.drug_class,
  COUNT(DISTINCT base.hadm_id) AS total_admissions,
  SUM(COALESCE(f12.flag_first_12h, 0)) AS count_first_12h,
  SUM(COALESCE(f48.flag_final_48h, 0)) AS count_final_48h,
  ROUND(SAFE_DIVIDE(SUM(COALESCE(f12.flag_first_12h, 0)), COUNT(DISTINCT base.hadm_id)) * 100, 2) AS rate_first_12h,
  ROUND(SAFE_DIVIDE(SUM(COALESCE(f48.flag_final_48h, 0)), COUNT(DISTINCT base.hadm_id)) * 100, 2) AS rate_final_48h,
  ROUND(
    (SAFE_DIVIDE(SUM(COALESCE(f48.flag_final_48h, 0)), COUNT(DISTINCT base.hadm_id)) * 100) -
    (SAFE_DIVIDE(SUM(COALESCE(f12.flag_first_12h, 0)), COUNT(DISTINCT base.hadm_id)) * 100),
  2
  ) AS net_change_pp
FROM base
LEFT JOIN first_12h f12
  ON base.hadm_id = f12.hadm_id AND base.drug_class = f12.drug_class
LEFT JOIN final_48h f48
  ON base.hadm_id = f48.hadm_id AND base.drug_class = f48.drug_class
GROUP BY base.drug_class
ORDER BY base.drug_class;