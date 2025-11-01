WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 54 AND 64
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '250%') OR
        (icd_version = 10 AND icd_code LIKE 'E1%')
    )
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%') OR
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),

prescriptions_initial AS (
  SELECT 
    c.hadm_id,
    COALESCE(MAX(
      CASE 
        WHEN 
          LOWER(pr.drug) LIKE '%insulin%' OR
          LOWER(pr.drug) LIKE '%humalog%' OR 
          LOWER(pr.drug) LIKE '%humulin%' OR 
          LOWER(pr.drug) LIKE '%novolog%' OR 
          LOWER(pr.drug) LIKE '%novolin%' OR 
          LOWER(pr.drug) LIKE '%apidra%' OR 
          LOWER(pr.drug) LIKE '%lantus%' OR 
          LOWER(pr.drug) LIKE '%levemir%' OR 
          LOWER(pr.drug) LIKE '%toujeo%' OR 
          LOWER(pr.drug) LIKE '%tresiba%' OR 
          LOWER(pr.drug) LIKE '%basaglar%' 
        THEN 1 
        ELSE 0 END
    ), 0) AS insulin_flag,
    COALESCE(MAX(
      CASE 
        WHEN 
          LOWER(pr.drug) LIKE '%metformin%' OR
          LOWER(pr.drug) LIKE '%glipizide%' OR 
          LOWER(pr.drug) LIKE '%glyburide%' OR 
          LOWER(pr.drug) LIKE '%glimepiride%' OR 
          LOWER(pr.drug) LIKE '%pioglitazone%' OR 
          LOWER(pr.drug) LIKE '%rosiglitazone%' OR 
          LOWER(pr.drug) LIKE '%repaglinide%' OR 
          LOWER(pr.drug) LIKE '%nateglinide%' OR 
          LOWER(pr.drug) LIKE '%sitagliptin%' OR 
          LOWER(pr.drug) LIKE '%saxagliptin%' OR 
          LOWER(pr.drug) LIKE '%linagliptin%' OR 
          LOWER(pr.drug) LIKE '%alogliptin%' OR 
          LOWER(pr.drug) LIKE '%canagliflozin%' OR 
          LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
          LOWER(pr.drug) LIKE '%empagliflozin%' OR 
          LOWER(pr.drug) LIKE '%acarbose%' OR 
          LOWER(pr.drug) LIKE '%miglitol%' 
        THEN 1 
        ELSE 0 END
    ), 0) AS oral_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR)
  GROUP BY c.hadm_id
),

prescriptions_final AS (
  SELECT 
    c.hadm_id,
    COALESCE(MAX(
      CASE 
        WHEN 
          LOWER(pr.drug) LIKE '%insulin%' OR
          LOWER(pr.drug) LIKE '%humalog%' OR 
          LOWER(pr.drug) LIKE '%humulin%' OR 
          LOWER(pr.drug) LIKE '%novolog%' OR 
          LOWER(pr.drug) LIKE '%novolin%' OR 
          LOWER(pr.drug) LIKE '%apidra%' OR 
          LOWER(pr.drug) LIKE '%lantus%' OR 
          LOWER(pr.drug) LIKE '%levemir%' OR 
          LOWER(pr.drug) LIKE '%toujeo%' OR 
          LOWER(pr.drug) LIKE '%tresiba%' OR 
          LOWER(pr.drug) LIKE '%basaglar%' 
        THEN 1 
        ELSE 0 END
    ), 0) AS insulin_flag,
    COALESCE(MAX(
      CASE 
        WHEN 
          LOWER(pr.drug) LIKE '%metformin%' OR
          LOWER(pr.drug) LIKE '%glipizide%' OR 
          LOWER(pr.drug) LIKE '%glyburide%' OR 
          LOWER(pr.drug) LIKE '%glimepiride%' OR 
          LOWER(pr.drug) LIKE '%pioglitazone%' OR 
          LOWER(pr.drug) LIKE '%rosiglitazone%' OR 
          LOWER(pr.drug) LIKE '%repaglinide%' OR 
          LOWER(pr.drug) LIKE '%nateglinide%' OR 
          LOWER(pr.drug) LIKE '%sitagliptin%' OR 
          LOWER(pr.drug) LIKE '%saxagliptin%' OR 
          LOWER(pr.drug) LIKE '%linagliptin%' OR 
          LOWER(pr.drug) LIKE '%alogliptin%' OR 
          LOWER(pr.drug) LIKE '%canagliflozin%' OR 
          LOWER(pr.drug) LIKE '%dapagliflozin%' OR 
          LOWER(pr.drug) LIKE '%empagliflozin%' OR 
          LOWER(pr.drug) LIKE '%acarbose%' OR 
          LOWER(pr.drug) LIKE '%miglitol%' 
        THEN 1 
        ELSE 0 END
    ), 0) AS oral_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr 
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 48 HOUR) AND c.dischtime
  GROUP BY c.hadm_id
)

SELECT 
  COUNT(*) AS total_patients,
  SUM(pi.insulin_flag) AS insulin_initial_count,
  SUM(pi.oral_flag) AS oral_initial_count,
  SUM(pf.insulin_flag) AS insulin_final_count,
  SUM(pf.oral_flag) AS oral_final_count,
  ROUND( (SUM(pi.insulin_flag) / COUNT(*)) * 100, 2 ) AS insulin_initial_pct,
  ROUND( (SUM(pi.oral_flag) / COUNT(*)) * 100, 2 ) AS oral_initial_pct,
  ROUND( (SUM(pf.insulin_flag) / COUNT(*)) * 100, 2 ) AS insulin_final_pct,
  ROUND( (SUM(pf.oral_flag) / COUNT(*)) * 100, 2 ) AS oral_final_pct,
  ROUND( (SUM(pf.insulin_flag) - SUM(pi.insulin_flag)) * 100.0 / COUNT(*), 2 ) AS insulin_net_change_pp,
  ROUND( (SUM(pf.oral_flag) - SUM(pi.oral_flag)) * 100.0 / COUNT(*), 2 ) AS oral_net_change_pp
FROM cohort c
LEFT JOIN prescriptions_initial pi ON c.hadm_id = pi.hadm_id
LEFT JOIN prescriptions_final pf ON c.hadm_id = pf.hadm_id;