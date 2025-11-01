WITH patient_cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 66 AND 76
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
diabetes_hf AS (
  SELECT 
    pc.hadm_id
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di 
    ON pc.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%diabetes%'
  INTERSECT DISTINCT
  SELECT 
    pc.hadm_id
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di 
    ON pc.hadm_id = di.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
    OR LOWER(d.long_title) LIKE '%hf%'
),
antidiabetic_classes AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    p.starttime,
    p.stoptime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimiperide%' THEN 'Sulfonylureas'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' THEN 'DPP-4 Inhibitors'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' THEN 'SGLT2 Inhibitors'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%exenatide%' THEN 'GLP-1 Agonists'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      WHEN LOWER(p.drug) LIKE '%acarbose%' THEN 'Alpha-glucosidase Inhibitors'
      WHEN LOWER(p.drug) LIKE '%nateglinide%' OR LOWER(p.drug) LIKE '%repaglinide%' THEN 'Meglitinides'
      ELSE 'Other'
    END AS drug_class
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p 
    ON pc.hadm_id = p.hadm_id
  WHERE 
    LOWER(p.drug) LIKE '%insulin%'
    OR LOWER(p.drug) LIKE '%metformin%'
    OR LOWER(p.drug) LIKE '%glipizide%'
    OR LOWER(p.drug) LIKE '%glyburide%'
    OR LOWER(p.drug) LIKE '%glimiperide%'
    OR LOWER(p.drug) LIKE '%sitagliptin%'
    OR LOWER(p.drug) LIKE '%saxagliptin%'
    OR LOWER(p.drug) LIKE '%linagliptin%'
    OR LOWER(p.drug) LIKE '%empagliflozin%'
    OR LOWER(p.drug) LIKE '%dapagliflozin%'
    OR LOWER(p.drug) LIKE '%canagliflozin%'
    OR LOWER(p.drug) LIKE '%liraglutide%'
    OR LOWER(p.drug) LIKE '%semaglutide%'
    OR LOWER(p.drug) LIKE '%exenatide%'
    OR LOWER(p.drug) LIKE '%pioglitazone%'
    OR LOWER(p.drug) LIKE '%rosiglitazone%'
    OR LOWER(p.drug) LIKE '%acarbose%'
    OR LOWER(p.drug) LIKE '%nateglinide%'
    OR LOWER(p.drug) LIKE '%repaglinide%'
),
time_windows AS (
  SELECT 
    subject_id,
    hadm_id,
    drug_class,
    -- First 72h: drug started within 72h of admission
    MAX(CASE WHEN starttime >= admittime AND starttime < DATETIME_ADD(admittime, INTERVAL 72 HOUR) THEN 1 ELSE 0 END) AS in_first_72h,
    -- Final 24h: drug was active in last 24h before discharge
    MAX(CASE 
      WHEN (starttime <= DATETIME_SUB(dischtime, INTERVAL 24 HOUR) AND (stoptime IS NULL OR stoptime >= DATETIME_SUB(dischtime, INTERVAL 24 HOUR)))
        OR (starttime > DATETIME_SUB(dischtime, INTERVAL 24 HOUR) AND starttime <= dischtime)
        THEN 1 ELSE 0 
      END) AS in_final_24h
  FROM (
    SELECT 
      ac.subject_id,
      ac.hadm_id,
      ac.drug_class,
      ac.starttime,
      COALESCE(ac.stoptime, pc.dischtime) AS stoptime,
      pc.admittime,
      pc.dischtime
    FROM antidiabetic_classes ac
    INNER JOIN patient_cohort pc ON ac.hadm_id = pc.hadm_id
    WHERE ac.drug_class != 'Other'
  )
  GROUP BY subject_id, hadm_id, drug_class
),
class_usage AS (
  SELECT 
    drug_class,
    AVG(in_first_72h) * 100 AS pct_first_72h,
    AVG(in_final_24h) * 100 AS pct_final_24h
  FROM time_windows
  GROUP BY drug_class
)
SELECT 
  drug_class,
  ROUND(pct_first_72h, 2) AS pct_first_72h,
  ROUND(pct_final_24h, 2) AS pct_final_24h
FROM class_usage
ORDER BY drug_class;