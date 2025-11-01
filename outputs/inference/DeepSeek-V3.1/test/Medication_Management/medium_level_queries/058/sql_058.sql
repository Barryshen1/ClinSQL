WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.anchor_age BETWEEN 36 AND 46
    AND pat.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'E11%') 
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '250.00')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_version = 10 AND diag.icd_code LIKE 'I50%')
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '428%')
        )
    )
),

antidiabetic_orders AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    p.starttime,
    p.drug,
    CASE 
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1 agonist'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      ELSE NULL 
    END AS drug_class
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime BETWEEN c.admittime AND c.dischtime
    AND CASE 
          WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanide'
          WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
          WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' THEN 'DPP-4 inhibitor'
          WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1 agonist'
          WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' THEN 'SGLT2 inhibitor'
          WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
          ELSE NULL 
        END IS NOT NULL
),

class_flags AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime,
    -- For each class, check if initiated in first 12h
    MAX(CASE WHEN drug_class = 'Biguanide' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS biguanide_first12h,
    MAX(CASE WHEN drug_class = 'Sulfonylurea' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS sulfonylurea_first12h,
    MAX(CASE WHEN drug_class = 'DPP-4 inhibitor' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS dpp4_first12h,
    MAX(CASE WHEN drug_class = 'GLP-1 agonist' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS glp1_first12h,
    MAX(CASE WHEN drug_class = 'SGLT2 inhibitor' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS sglt2_first12h,
    MAX(CASE WHEN drug_class = 'Insulin' AND starttime BETWEEN admittime AND DATETIME_ADD(admittime, INTERVAL 12 HOUR) THEN 1 ELSE 0 END) AS insulin_first12h,

    -- For each class, check if initiated in last 48h
    MAX(CASE WHEN drug_class = 'Biguanide' AND starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS biguanide_last48h,
    MAX(CASE WHEN drug_class = 'Sulfonylurea' AND starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS sulfonylurea_last48h,
    MAX(CASE WHEN drug_class = 'DPP-4 inhibitor' AND starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS dpp4_last48h,
    MAX(CASE WHEN drug_class = 'GLP-1 agonist' AND starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS glp1_last48h,
    MAX(CASE WHEN drug_class = 'SGLT2 inhibitor' AND starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS sglt2_last48h,
    MAX(CASE WHEN drug_class = 'Insulin' AND starttime BETWEEN DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AND dischtime THEN 1 ELSE 0 END) AS insulin_last48h
  FROM antidiabetic_orders
  GROUP BY hadm_id, admittime, dischtime
),

cohort_with_flags AS (
  SELECT 
    c.hadm_id,
    COALESCE(cf.biguanide_first12h, 0) AS biguanide_first12h,
    COALESCE(cf.sulfonylurea_first12h, 0) AS sulfonylurea_first12h,
    COALESCE(cf.dpp4_first12h, 0) AS dpp4_first12h,
    COALESCE(cf.glp1_first12h, 0) AS glp1_first12h,
    COALESCE(cf.sglt2_first12h, 0) AS sglt2_first12h,
    COALESCE(cf.insulin_first12h, 0) AS insulin_first12h,
    COALESCE(cf.biguanide_last48h, 0) AS biguanide_last48h,
    COALESCE(cf.sulfonylurea_last48h, 0) AS sulfonylurea_last48h,
    COALESCE(cf.dpp4_last48h, 0) AS dpp4_last48h,
    COALESCE(cf.glp1_last48h, 0) AS glp1_last48h,
    COALESCE(cf.sglt2_last48h, 0) AS sglt2_last48h,
    COALESCE(cf.insulin_last48h, 0) AS insulin_last48h
  FROM cohort c
  LEFT JOIN class_flags cf
    ON c.hadm_id = cf.hadm_id
)

SELECT 
  'Biguanide' AS drug_class,
  ROUND(100 * AVG(biguanide_first12h), 2) AS init_rate_first12h,
  ROUND(100 * AVG(biguanide_last48h), 2) AS init_rate_last48h,
  ROUND(100 * AVG(biguanide_last48h) - 100 * AVG(biguanide_first12h), 2) AS net_change_pp
FROM cohort_with_flags
UNION ALL
SELECT 
  'Sulfonylurea',
  ROUND(100 * AVG(sulfonylurea_first12h), 2),
  ROUND(100 * AVG(sulfonylurea_last48h), 2),
  ROUND(100 * AVG(sulfonylurea_last48h) - 100 * AVG(sulfonylurea_first12h), 2)
FROM cohort_with_flags
UNION ALL
SELECT 
  'DPP-4 inhibitor',
  ROUND(100 * AVG(dpp4_first12h), 2),
  ROUND(100 * AVG(dpp4_last48h), 2),
  ROUND(100 * AVG(dpp4_last48h) - 100 * AVG(dpp4_first12h), 2)
FROM cohort_with_flags
UNION ALL
SELECT 
  'GLP-1 agonist',
  ROUND(100 * AVG(glp1_first12h), 2),
  ROUND(100 * AVG(glp1_last48h), 2),
  ROUND(100 * AVG(glp1_last48h) - 100 * AVG(glp1_first12h), 2)
FROM cohort_with_flags
UNION ALL
SELECT 
  'SGLT2 inhibitor',
  ROUND(100 * AVG(sglt2_first12h), 2),
  ROUND(100 * AVG(sglt2_last48h), 2),
  ROUND(100 * AVG(sglt2_last48h) - 100 * AVG(sglt2_first12h), 2)
FROM cohort_with_flags
UNION ALL
SELECT 
  'Insulin',
  ROUND(100 * AVG(insulin_first12h), 2),
  ROUND(100 * AVG(insulin_last48h), 2),
  ROUND(100 * AVG(insulin_last48h) - 100 * AVG(insulin_first12h), 2)
FROM cohort_with_flags
ORDER BY drug_class;