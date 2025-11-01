WITH diag AS (
  SELECT 
    hadm_id,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '250%') 
             OR (icd_version = 10 AND icd_code LIKE 'E1%') THEN 1 
          ELSE 0 
        END) AS diabetes,
    MAX(CASE 
          WHEN (icd_version = 9 AND icd_code LIKE '428%') 
             OR (icd_version = 10 AND icd_code LIKE 'I50%') THEN 1 
          ELSE 0 
        END) AS heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  GROUP BY hadm_id
),

cohort AS (
  SELECT 
    pat.subject_id, 
    adm.hadm_id, 
    icu.stay_id,
    icu.intime, 
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm 
    ON pat.subject_id = adm.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu 
    ON adm.hadm_id = icu.hadm_id
  INNER JOIN diag 
    ON adm.hadm_id = diag.hadm_id
  WHERE 
    pat.gender = 'M'
    AND diag.diabetes = 1 
    AND diag.heart_failure = 1  -- Added missing AND
    AND TIMESTAMP_DIFF(icu.outtime, icu.intime, HOUR) >= 72  -- Changed to TIMESTAMP_DIFF
    AND (pat.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year)) BETWEEN 66 AND 76
  QUALIFY ROW_NUMBER() OVER (PARTITION BY adm.hadm_id ORDER BY icu.intime) = 1
),

cohort_count AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM cohort
),

antidiabetic_classes AS (
  SELECT 
    LOWER(drug) AS drug_lower,
    CASE 
      WHEN LOWER(drug) LIKE '%insulin%' OR 
           LOWER(drug) LIKE '%humulin%' OR 
           LOWER(drug) LIKE '%novolin%' OR 
           LOWER(drug) LIKE '%lantus%' OR 
           LOWER(drug) LIKE '%levemir%' OR 
           LOWER(drug) LIKE '%apidra%' OR 
           LOWER(drug) LIKE '%tresiba%' OR 
           LOWER(drug) LIKE '%humalog%' OR 
           LOWER(drug) LIKE '%novolog%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Biguanides'
      WHEN LOWER(drug) LIKE '%glipizide%' OR 
           LOWER(drug) LIKE '%glyburide%' OR 
           LOWER(drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(drug) LIKE '%repaglinide%' OR 
           LOWER(drug) LIKE '%nateglinide%' THEN 'Meglitinides'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR 
           LOWER(drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR 
           LOWER(drug) LIKE '%saxagliptin%' OR 
           LOWER(drug) LIKE '%linagliptin%' OR 
           LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4 inhibitors'
      WHEN LOWER(drug) LIKE '%exenatide%' OR 
           LOWER(drug) LIKE '%liraglutide%' OR 
           LOWER(drug) LIKE '%dulaglutide%' OR 
           LOWER(drug) LIKE '%semaglutide%' THEN 'GLP-1 receptor agonists'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR 
           LOWER(drug) LIKE '%dapagliflozin%' OR 
           LOWER(drug) LIKE '%empagliflozin%' THEN 'SGLT2 inhibitors'
      ELSE NULL 
    END AS drug_class
  FROM (SELECT DISTINCT drug FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`)
),

prescriptions_in_cohort AS (
  SELECT 
    p.hadm_id,
    p.drug,
    p.starttime,
    p.stoptime,
    ac.drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort c 
    ON p.hadm_id = c.hadm_id
  INNER JOIN antidiabetic_classes ac 
    ON LOWER(p.drug) = ac.drug_lower
  WHERE ac.drug_class IS NOT NULL
),

class_usage AS (
  SELECT 
    c.hadm_id,
    p.drug_class,
    MAX(CASE 
          WHEN p.starttime <= TIMESTAMP_ADD(c.intime, INTERVAL 72 HOUR)  -- Changed to TIMESTAMP_ADD
            AND (p.stoptime IS NULL OR p.stoptime >= c.intime) 
          THEN 1 ELSE 0 
        END) AS in_first_72h,
    MAX(CASE 
          WHEN p.starttime <= c.outtime 
            AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(c.outtime, INTERVAL 24 HOUR))  -- Changed to TIMESTAMP_SUB
          THEN 1 ELSE 0 
        END) AS in_final_24h
  FROM cohort c
  LEFT JOIN prescriptions_in_cohort p 
    ON c.hadm_id = p.hadm_id
  GROUP BY c.hadm_id, p.drug_class
)

SELECT 
  drug_class,
  ROUND(SUM(in_first_72h) * 100.0 / cc.total, 2) AS pct_first_72h,
  ROUND(SUM(in_final_24h) * 100.0 / cc.total, 2) AS pct_final_24h
FROM class_usage
CROSS JOIN cohort_count cc
WHERE drug_class IS NOT NULL
GROUP BY drug_class, cc.total
ORDER BY drug_class;