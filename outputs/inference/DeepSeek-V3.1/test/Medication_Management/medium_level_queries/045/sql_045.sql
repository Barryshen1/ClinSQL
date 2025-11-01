WITH cohort AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime, 
    adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 54 AND 64
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE diag.subject_id = adm.subject_id
        AND diag.hadm_id = adm.hadm_id
        AND (
          (diag.icd_code LIKE '250%' OR diag.icd_code LIKE 'E10%' OR diag.icd_code LIKE 'E11%')
          AND (diag.icd_code LIKE '428%' OR diag.icd_code LIKE 'I50%')
        )
    )
),

insulin_first_12h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS insulin_12h_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
  GROUP BY c.hadm_id
),

insulin_last_48h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS insulin_48h_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  GROUP BY c.hadm_id
),

oral_first_12h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS oral_12h_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE (LOWER(p.drug) LIKE '%metformin%' 
      OR LOWER(p.drug) LIKE '%glipizide%'
      OR LOWER(p.drug) LIKE '%glyburide%'
      OR LOWER(p.drug) LIKE '%glimepiride%'
      OR LOWER(p.drug) LIKE '%pioglitazone%'
      OR LOWER(p.drug) LIKE '%repaglinide%'
      OR LOWER(p.drug) LIKE '%nateglinide%'
      OR LOWER(p.drug) LIKE '%sitagliptin%'
      OR LOWER(p.drug) LIKE '%saxagliptin%'
      OR LOWER(p.drug) LIKE '%linagliptin%'
      OR LOWER(p.drug) LIKE '%empagliflozin%'
      OR LOWER(p.drug) LIKE '%canagliflozin%'
      OR LOWER(p.drug) LIKE '%dapagliflozin%'
      OR LOWER(p.drug) LIKE '%tolbutamide%'
      OR LOWER(p.drug) LIKE '%acarbose%'
      OR LOWER(p.drug) LIKE '%miglitol%')
    AND p.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
  GROUP BY c.hadm_id
),

oral_last_48h AS (
  SELECT 
    c.hadm_id,
    MAX(1) AS oral_48h_flag
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE (LOWER(p.drug) LIKE '%metformin%' 
      OR LOWER(p.drug) LIKE '%glipizide%'
      OR LOWER(p.drug) LIKE '%glyburide%'
      OR LOWER(p.drug) LIKE '%glimepiride%'
      OR LOWER(p.drug) LIKE '%pioglitazone%'
      OR LOWER(p.drug) LIKE '%repaglinide%'
      OR LOWER(p.drug) LIKE '%nateglinide%'
      OR LOWER(p.drug) LIKE '%sitagliptin%'
      OR LOWER(p.drug) LIKE '%saxagliptin%'
      OR LOWER(p.drug) LIKE '%linagliptin%'
      OR LOWER(p.drug) LIKE '%empagliflozin%'
      OR LOWER(p.drug) LIKE '%canagliflozin%'
      OR LOWER(p.drug) LIKE '%dapagliflozin%'
      OR LOWER(p.drug) LIKE '%tolbutamide%'
      OR LOWER(p.drug) LIKE '%acarbose%'
      OR LOWER(p.drug) LIKE '%miglitol%')
    AND p.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  GROUP BY c.hadm_id
)

SELECT 
  'Insulin' AS drug_class,
  COUNT(ins12.hadm_id) AS count_first_12h,
  ROUND(100.0 * COUNT(ins12.hadm_id) / COUNT(*), 2) AS prevalence_first_12h,
  COUNT(ins48.hadm_id) AS count_final_48h,
  ROUND(100.0 * COUNT(ins48.hadm_id) / COUNT(*), 2) AS prevalence_final_48h,
  ROUND(100.0 * COUNT(ins48.hadm_id) / COUNT(*) - 100.0 * COUNT(ins12.hadm_id) / COUNT(*), 2) AS net_change_pp
FROM cohort c
LEFT JOIN insulin_first_12h ins12 ON c.hadm_id = ins12.hadm_id
LEFT JOIN insulin_last_48h ins48 ON c.hadm_id = ins48.hadm_id
GROUP BY drug_class

UNION ALL

SELECT 
  'Oral Agent' AS drug_class,
  COUNT(oral12.hadm_id) AS count_first_12h,
  ROUND(100.0 * COUNT(oral12.hadm_id) / COUNT(*), 2) AS prevalence_first_12h,
  COUNT(oral48.hadm_id) AS count_final_48h,
  ROUND(100.0 * COUNT(oral48.hadm_id) / COUNT(*), 2) AS prevalence_final_48h,
  ROUND(100.0 * COUNT(oral48.hadm_id) / COUNT(*) - 100.0 * COUNT(oral12.hadm_id) / COUNT(*), 2) AS net_change_pp
FROM cohort c
LEFT JOIN oral_first_12h oral12 ON c.hadm_id = oral12.hadm_id
LEFT JOIN oral_last_48h oral48 ON c.hadm_id = oral48.hadm_id
GROUP BY drug_class;