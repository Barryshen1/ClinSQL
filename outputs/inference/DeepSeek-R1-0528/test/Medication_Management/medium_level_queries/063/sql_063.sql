WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    -- Diabetes diagnosis (ICD-9: 250.x; ICD-10: E10-E14)
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '250%') 
        OR 
        (icd_version = 10 AND icd_code LIKE 'E1%')
    )
    -- Heart failure diagnosis (ICD-9: 428.x; ICD-10: I50.x)
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE 
        (icd_version = 9 AND icd_code LIKE '428%') 
        OR 
        (icd_version = 10 AND icd_code LIKE 'I50%')
    )
),

insulin_first AS (
  SELECT 
    hadm_id,
    MIN(starttime) AS first_insulin_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%insulin%'
    OR LOWER(drug) LIKE '%lantus%'
    OR LOWER(drug) LIKE '%levemir%'
    OR LOWER(drug) LIKE '%novolog%'
    OR LOWER(drug) LIKE '%humalog%'
    OR LOWER(drug) LIKE '%apidra%'
    OR LOWER(drug) LIKE '%tresiba%'
  GROUP BY hadm_id
),

oral_first AS (
  SELECT 
    hadm_id,
    MIN(starttime) AS first_oral_time
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE 
    LOWER(drug) LIKE '%metformin%'
    OR LOWER(drug) LIKE '%glipizide%'
    OR LOWER(drug) LIKE '%glyburide%'
    OR LOWER(drug) LIKE '%glimepiride%'
    OR LOWER(drug) LIKE '%pioglitazone%'
    OR LOWER(drug) LIKE '%rosiglitazone%'
    OR LOWER(drug) LIKE '%sitagliptin%'
    OR LOWER(drug) LIKE '%linagliptin%'
    OR LOWER(drug) LIKE '%saxagliptin%'
    OR LOWER(drug) LIKE '%dapagliflozin%'
    OR LOWER(drug) LIKE '%empagliflozin%'
    OR LOWER(drug) LIKE '%canagliflozin%'
    OR LOWER(drug) LIKE '%repaglinide%'
  GROUP BY hadm_id
),

cohort_meds AS (
  SELECT 
    c.hadm_id,
    c.admittime,
    c.dischtime,
    -- Insulin indicators
    CASE 
        WHEN i.first_insulin_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) 
        THEN 1 ELSE 0 
    END AS insulin_first_12h,
    CASE 
        WHEN i.first_insulin_time BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime 
        THEN 1 ELSE 0 
    END AS insulin_final_72h,
    -- Oral antidiabetic indicators
    CASE 
        WHEN o.first_oral_time BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 12 HOUR) 
        THEN 1 ELSE 0 
    END AS oral_first_12h,
    CASE 
        WHEN o.first_oral_time BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 72 HOUR) AND c.dischtime 
        THEN 1 ELSE 0 
    END AS oral_final_72h
  FROM cohort c
  LEFT JOIN insulin_first i ON c.hadm_id = i.hadm_id
  LEFT JOIN oral_first o ON c.hadm_id = o.hadm_id
)

SELECT 
  'Insulin' AS medication_class,
  COUNT(*) AS total_admissions,
  SUM(insulin_first_12h) AS count_first_12h,
  ROUND(100.0 * SUM(insulin_first_12h) / COUNT(*), 2) AS rate_first_12h,
  SUM(insulin_final_72h) AS count_final_72h,
  ROUND(100.0 * SUM(insulin_final_72h) / COUNT(*), 2) AS rate_final_72h,
  ROUND(100.0 * SUM(insulin_first_12h) / COUNT(*), 2) - ROUND(100.0 * SUM(insulin_final_72h) / COUNT(*), 2) AS pp_difference
FROM cohort_meds

UNION ALL

SELECT 
  'Oral Antidiabetics' AS medication_class,
  COUNT(*) AS total_admissions,
  SUM(oral_first_12h) AS count_first_12h,
  ROUND(100.0 * SUM(oral_first_12h) / COUNT(*), 2) AS rate_first_12h,
  SUM(oral_final_72h) AS count_final_72h,
  ROUND(100.0 * SUM(oral_final_72h) / COUNT(*), 2) AS rate_final_72h,
  ROUND(100.0 * SUM(oral_first_12h) / COUNT(*), 2) - ROUND(100.0 * SUM(oral_final_72h) / COUNT(*), 2) AS pp_difference
FROM cohort_meds;