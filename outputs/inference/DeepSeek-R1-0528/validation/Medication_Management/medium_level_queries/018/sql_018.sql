WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    DATETIME_ADD(adm.admittime, INTERVAL 72 HOUR) AS end_72h,
    GREATEST(adm.admittime, DATETIME_SUB(adm.dischtime, INTERVAL 48 HOUR)) AS start_48h
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'F'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE diag.hadm_id = adm.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '250%' AND RIGHT(diag.icd_code, 1) IN ('0','2'))
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag 
      WHERE diag.hadm_id = adm.hadm_id 
        AND (
          (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
          OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
        )
    )
),

prescriptions_72h AS (
  SELECT 
    p.hadm_id,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%glipizide%' OR 
           LOWER(p.drug) LIKE '%glyburide%' OR 
           LOWER(p.drug) LIKE '%glimepiride%' OR 
           LOWER(p.drug) LIKE '%gliclazide%' OR 
           LOWER(p.drug) LIKE '%sulfonylurea%' 
         THEN 1 ELSE 0 END) AS sulfonylurea,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%sitagliptin%' OR 
           LOWER(p.drug) LIKE '%saxagliptin%' OR 
           LOWER(p.drug) LIKE '%linagliptin%' OR 
           LOWER(p.drug) LIKE '%alogliptin%' OR 
           LOWER(p.drug) LIKE '%dpp4%' OR 
           LOWER(p.drug) LIKE '%dipeptidyl peptidase%' 
         THEN 1 ELSE 0 END) AS dpp4,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%canagliflozin%' OR 
           LOWER(p.drug) LIKE '%dapagliflozin%' OR 
           LOWER(p.drug) LIKE '%empagliflozin%' OR 
           LOWER(p.drug) LIKE '%sglt2%' OR 
           LOWER(p.drug) LIKE '%sodium-glucose%' 
         THEN 1 ELSE 0 END) AS sglt2,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%pioglitazone%' OR 
           LOWER(p.drug) LIKE '%rosiglitazone%' OR 
           LOWER(p.drug) LIKE '%thiazolidinedione%' OR 
           LOWER(p.drug) LIKE '%tzd%' 
         THEN 1 ELSE 0 END) AS tzd
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c 
    ON p.hadm_id = c.hadm_id
  WHERE 
    p.starttime <= c.end_72h 
    AND COALESCE(p.stoptime, c.dischtime) >= c.admittime
  GROUP BY p.hadm_id
),

prescriptions_48h AS (
  SELECT 
    p.hadm_id,
    MAX(CASE WHEN LOWER(p.drug) LIKE '%metformin%' THEN 1 ELSE 0 END) AS metformin,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%glipizide%' OR 
           LOWER(p.drug) LIKE '%glyburide%' OR 
           LOWER(p.drug) LIKE '%glimepiride%' OR 
           LOWER(p.drug) LIKE '%gliclazide%' OR 
           LOWER(p.drug) LIKE '%sulfonylurea%' 
         THEN 1 ELSE 0 END) AS sulfonylurea,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%sitagliptin%' OR 
           LOWER(p.drug) LIKE '%saxagliptin%' OR 
           LOWER(p.drug) LIKE '%linagliptin%' OR 
           LOWER(p.drug) LIKE '%alogliptin%' OR 
           LOWER(p.drug) LIKE '%dpp4%' OR 
           LOWER(p.drug) LIKE '%dipeptidyl peptidase%' 
         THEN 1 ELSE 0 END) AS dpp4,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%canagliflozin%' OR 
           LOWER(p.drug) LIKE '%dapagliflozin%' OR 
           LOWER(p.drug) LIKE '%empagliflozin%' OR 
           LOWER(p.drug) LIKE '%sglt2%' OR 
           LOWER(p.drug) LIKE '%sodium-glucose%' 
         THEN 1 ELSE 0 END) AS sglt2,
    MAX(CASE WHEN 
           LOWER(p.drug) LIKE '%pioglitazone%' OR 
           LOWER(p.drug) LIKE '%rosiglitazone%' OR 
           LOWER(p.drug) LIKE '%thiazolidinedione%' OR 
           LOWER(p.drug) LIKE '%tzd%' 
         THEN 1 ELSE 0 END) AS tzd
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c 
    ON p.hadm_id = c.hadm_id
  WHERE 
    p.starttime <= c.dischtime 
    AND COALESCE(p.stoptime, c.dischtime) >= c.start_48h
  GROUP BY p.hadm_id
),

classes AS (
  SELECT 'metformin' AS drug_class UNION ALL
  SELECT 'sulfonylurea' UNION ALL
  SELECT 'dpp4' UNION ALL
  SELECT 'sglt2' UNION ALL
  SELECT 'tzd'
),

per_admission AS (
  SELECT 
    c.hadm_id,
    cl.drug_class,
    CASE 
      WHEN cl.drug_class = 'metformin' THEN COALESCE(p72.metformin, 0)
      WHEN cl.drug_class = 'sulfonylurea' THEN COALESCE(p72.sulfonylurea, 0)
      WHEN cl.drug_class = 'dpp4' THEN COALESCE(p72.dpp4, 0)
      WHEN cl.drug_class = 'sglt2' THEN COALESCE(p72.sglt2, 0)
      WHEN cl.drug_class = 'tzd' THEN COALESCE(p72.tzd, 0)
    END AS flag_72h,
    CASE 
      WHEN cl.drug_class = 'metformin' THEN COALESCE(p48.metformin, 0)
      WHEN cl.drug_class = 'sulfonylurea' THEN COALESCE(p48.sulfonylurea, 0)
      WHEN cl.drug_class = 'dpp4' THEN COALESCE(p48.dpp4, 0)
      WHEN cl.drug_class = 'sglt2' THEN COALESCE(p48.sglt2, 0)
      WHEN cl.drug_class = 'tzd' THEN COALESCE(p48.tzd, 0)
    END AS flag_48h
  FROM cohort c
  CROSS JOIN classes cl
  LEFT JOIN prescriptions_72h p72 ON c.hadm_id = p72.hadm_id
  LEFT JOIN prescriptions_48h p48 ON c.hadm_id = p48.hadm_id
)

SELECT 
  drug_class,
  ROUND(AVG(flag_72h) * 100, 2) AS prevalence_first_72h,
  ROUND(AVG(flag_48h) * 100, 2) AS prevalence_final_48h,
  ROUND(ABS(AVG(flag_72h) * 100 - AVG(flag_48h) * 100), 2) AS absolute_pp_difference
FROM per_admission
GROUP BY drug_class
ORDER BY drug_class;