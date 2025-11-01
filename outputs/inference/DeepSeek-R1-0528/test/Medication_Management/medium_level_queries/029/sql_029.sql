WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime,
    -- Calculate age at admission
    pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year) AS age_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pt
    ON adm.subject_id = pt.subject_id
  WHERE pt.gender = 'F'
    -- Use expression directly in WHERE (fixes alias issue)
    AND (pt.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pt.anchor_year)) BETWEEN 69 AND 79
    -- T2DM diagnosis (ICD-9: 250.x0/x2; ICD-10: E11.x)
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '250.%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2'))
        OR (icd_version = 10 AND icd_code LIKE 'E11%')
    )
    -- Heart failure diagnosis (ICD-9: 428.x, 402.xx, 404.xx; ICD-10: I50.x, I11.0, I13.0, I13.2)
    AND adm.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND (icd_code LIKE '428%' OR icd_code LIKE '402%' OR icd_code LIKE '404%'))
        OR (icd_version = 10 AND (icd_code LIKE 'I50%' OR icd_code IN ('I11.0', 'I13.0', 'I13.2')))
    )
),

drug_flags AS (
  SELECT 
    c.hadm_id,
    -- Insulin
    MAX(CASE 
          WHEN p.starttime <= LEAST(DATETIME_ADD(c.admittime, INTERVAL 72 HOUR), c.dischtime)
            AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
            AND LOWER(p.drug) LIKE '%insulin%' 
          THEN 1 ELSE 0 
        END) AS insulin_first_72,
    MAX(CASE 
          WHEN p.starttime <= c.dischtime
            AND (p.stoptime >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) OR p.stoptime IS NULL)
            AND LOWER(p.drug) LIKE '%insulin%' 
          THEN 1 ELSE 0 
        END) AS insulin_last_72,
    
    -- Metformin
    MAX(CASE 
          WHEN p.starttime <= LEAST(DATETIME_ADD(c.admittime, INTERVAL 72 HOUR), c.dischtime)
            AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
            AND LOWER(p.drug) LIKE '%metformin%' 
          THEN 1 ELSE 0 
        END) AS metformin_first_72,
    MAX(CASE 
          WHEN p.starttime <= c.dischtime
            AND (p.stoptime >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) OR p.stoptime IS NULL)
            AND LOWER(p.drug) LIKE '%metformin%' 
          THEN 1 ELSE 0 
        END) AS metformin_last_72,
    
    -- Sulfonylurea
    MAX(CASE 
          WHEN p.starttime <= LEAST(DATETIME_ADD(c.admittime, INTERVAL 72 HOUR), c.dischtime)
            AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%glipizide%' 
                 OR LOWER(p.drug) LIKE '%glyburide%' 
                 OR LOWER(p.drug) LIKE '%glimepiride%' 
                 OR LOWER(p.drug) LIKE '%gliclazide%')
          THEN 1 ELSE 0 
        END) AS sulfonylurea_first_72,
    MAX(CASE 
          WHEN p.starttime <= c.dischtime
            AND (p.stoptime >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%glipizide%' 
                 OR LOWER(p.drug) LIKE '%glyburide%' 
                 OR LOWER(p.drug) LIKE '%glimepiride%' 
                 OR LOWER(p.drug) LIKE '%gliclazide%')
          THEN 1 ELSE 0 
        END) AS sulfonylurea_last_72,
    
    -- DPP-4
    MAX(CASE 
          WHEN p.starttime <= LEAST(DATETIME_ADD(c.admittime, INTERVAL 72 HOUR), c.dischtime)
            AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%sitagliptin%' 
                 OR LOWER(p.drug) LIKE '%saxagliptin%' 
                 OR LOWER(p.drug) LIKE '%linagliptin%' 
                 OR LOWER(p.drug) LIKE '%alogliptin%')
          THEN 1 ELSE 0 
        END) AS dpp4_first_72,
    MAX(CASE 
          WHEN p.starttime <= c.dischtime
            AND (p.stoptime >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%sitagliptin%' 
                 OR LOWER(p.drug) LIKE '%saxagliptin%' 
                 OR LOWER(p.drug) LIKE '%linagliptin%' 
                 OR LOWER(p.drug) LIKE '%alogliptin%')
          THEN 1 ELSE 0 
        END) AS dpp4_last_72,
    
    -- SGLT2
    MAX(CASE 
          WHEN p.starttime <= LEAST(DATETIME_ADD(c.admittime, INTERVAL 72 HOUR), c.dischtime)
            AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%canagliflozin%' 
                 OR LOWER(p.drug) LIKE '%dapagliflozin%' 
                 OR LOWER(p.drug) LIKE '%empagliflozin%' 
                 OR LOWER(p.drug) LIKE '%ertugliflozin%')
          THEN 1 ELSE 0 
        END) AS sglt2_first_72,
    MAX(CASE 
          WHEN p.starttime <= c.dischtime
            AND (p.stoptime >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%canagliflozin%' 
                 OR LOWER(p.drug) LIKE '%dapagliflozin%' 
                 OR LOWER(p.drug) LIKE '%empagliflozin%' 
                 OR LOWER(p.drug) LIKE '%ertugliflozin%')
          THEN 1 ELSE 0 
        END) AS sglt2_last_72,
    
    -- GLP-1
    MAX(CASE 
          WHEN p.starttime <= LEAST(DATETIME_ADD(c.admittime, INTERVAL 72 HOUR), c.dischtime)
            AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%exenatide%' 
                 OR LOWER(p.drug) LIKE '%liraglutide%' 
                 OR LOWER(p.drug) LIKE '%dulaglutide%' 
                 OR LOWER(p.drug) LIKE '%semaglutide%')
          THEN 1 ELSE 0 
        END) AS glp1_first_72,
    MAX(CASE 
          WHEN p.starttime <= c.dischtime
            AND (p.stoptime >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%exenatide%' 
                 OR LOWER(p.drug) LIKE '%liraglutide%' 
                 OR LOWER(p.drug) LIKE '%dulaglutide%' 
                 OR LOWER(p.drug) LIKE '%semaglutide%')
          THEN 1 ELSE 0 
        END) AS glp1_last_72,
    
    -- TZD
    MAX(CASE 
          WHEN p.starttime <= LEAST(DATETIME_ADD(c.admittime, INTERVAL 72 HOUR), c.dischtime)
            AND (p.stoptime >= c.admittime OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%pioglitazone%' 
                 OR LOWER(p.drug) LIKE '%rosiglitazone%')
          THEN 1 ELSE 0 
        END) AS tzd_first_72,
    MAX(CASE 
          WHEN p.starttime <= c.dischtime
            AND (p.stoptime >= GREATEST(c.admittime, DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR)) OR p.stoptime IS NULL)
            AND (LOWER(p.drug) LIKE '%pioglitazone%' 
                 OR LOWER(p.drug) LIKE '%rosiglitazone%')
          THEN 1 ELSE 0 
        END) AS tzd_last_72
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id
)

SELECT 
  COUNT(hadm_id) AS total_admissions,
  ROUND(100 * AVG(insulin_first_72), 1) AS pct_insulin_first_72h,
  ROUND(100 * AVG(insulin_last_72), 1) AS pct_insulin_last_72h,
  ROUND(100 * AVG(metformin_first_72), 1) AS pct_metformin_first_72h,
  ROUND(100 * AVG(metformin_last_72), 1) AS pct_metformin_last_72h,
  ROUND(100 * AVG(sulfonylurea_first_72), 1) AS pct_sulfonylurea_first_72h,
  ROUND(100 * AVG(sulfonylurea_last_72), 1) AS pct_sulfonylurea_last_72h,
  ROUND(100 * AVG(dpp4_first_72), 1) AS pct_dpp4_first_72h,
  ROUND(100 * AVG(dpp4_last_72), 1) AS pct_dpp4_last_72h,
  ROUND(100 * AVG(sglt2_first_72), 1) AS pct_sglt2_first_72h,
  ROUND(100 * AVG(sglt2_last_72), 1) AS pct_sglt2_last_72h,
  ROUND(100 * AVG(glp1_first_72), 1) AS pct_glp1_first_72h,
  ROUND(100 * AVG(glp1_last_72), 1) AS pct_glp1_last_72h,
  ROUND(100 * AVG(tzd_first_72), 1) AS pct_tzd_first_72h,
  ROUND(100 * AVG(tzd_last_72), 1) AS pct_tzd_last_72h
FROM drug_flags;