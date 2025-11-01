WITH patients_with_birth AS (
  SELECT 
    subject_id,
    gender,  -- Added to resolve error
    anchor_year,
    anchor_age,
    DATE_SUB(CAST(CONCAT(CAST(anchor_year AS STRING), '-01-01') AS DATE), INTERVAL anchor_age YEAR) AS birth_date
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
),
cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) AS age_at_admission
  FROM patients_with_birth p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND a.dischtime IS NOT NULL
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
    AND TIMESTAMP_DIFF(a.admittime, p.birth_date, YEAR) BETWEEN 66 AND 76
),
conditions AS (
  SELECT 
    d.hadm_id,
    MAX(CASE 
          WHEN (dd.icd_version = 9 AND dd.icd_code LIKE '250%') 
             OR (dd.icd_version = 10 AND (dd.icd_code LIKE 'E10%' OR dd.icd_code LIKE 'E11%')) 
          THEN 1 ELSE 0 
        END) AS has_diabetes,
    MAX(CASE 
          WHEN (dd.icd_version = 9 AND dd.icd_code LIKE '428%') 
             OR (dd.icd_version = 10 AND dd.icd_code LIKE 'I50%') 
          THEN 1 ELSE 0 
        END) AS has_heart_failure
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd 
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  GROUP BY d.hadm_id
),
final_cohort AS (
  SELECT c.*
  FROM cohort c
  JOIN conditions cond 
    ON c.hadm_id = cond.hadm_id
  WHERE cond.has_diabetes = 1 AND cond.has_heart_failure = 1
),
first72h_drugs AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    LOWER(p.drug) AS drug,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR LOWER(p.drug) LIKE '%vildagliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
      WHEN LOWER(p.drug) LIKE '%acarbose%' OR LOWER(p.drug) LIKE '%miglitol%' OR LOWER(p.drug) LIKE '%dexfenfluramine%' THEN 'Alpha-glucosidase inhibitor'
      WHEN LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' THEN 'Meglitinide'
      WHEN LOWER(p.drug) LIKE '%colesevelam%' THEN 'Bile acid sequestrant'
      WHEN LOWER(p.drug) LIKE '%bromocriptine%' THEN 'Dopamine agonist'
      WHEN LOWER(p.drug) LIKE '%pramlintide%' THEN 'Amylin analog'
      ELSE NULL 
    END AS drug_class
  FROM final_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime >= c.admittime 
    AND p.starttime <= c.admittime + INTERVAL 72 HOUR
    AND p.drug_type = 'Medication'
    AND p.drug IS NOT NULL
    AND drug_class IS NOT NULL
),
final24h_drugs AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    LOWER(p.drug) AS drug,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Biguanide'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR LOWER(p.drug) LIKE '%vildagliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
      WHEN LOWER(p.drug) LIKE '%acarbose%' OR LOWER(p.drug) LIKE '%miglitol%' OR LOWER(p.drug) LIKE '%dexfenfluramine%' THEN 'Alpha-glucosidase inhibitor'
      WHEN LOWER(p.drug) LIKE '%repaglinide%' OR LOWER(p.drug) LIKE '%nateglinide%' THEN 'Meglitinide'
      WHEN LOWER(p.drug) LIKE '%colesevelam%' THEN 'Bile acid sequestrant'
      WHEN LOWER(p.drug) LIKE '%bromocriptine%' THEN 'Dopamine agonist'
      WHEN LOWER(p.drug) LIKE '%pramlintide%' THEN 'Amylin analog'
      ELSE NULL 
    END AS drug_class
  FROM final_cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p 
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime <= c.dischtime 
    AND (p.stoptime IS NULL OR p.stoptime >= c.dischtime - INTERVAL 24 HOUR)
    AND p.drug_type = 'Medication'
    AND p.drug IS NOT NULL
    AND drug_class IS NOT NULL
),
patient_class_flags AS (
  SELECT 
    c.hadm_id,
    c.subject_id,
    drug_class,
    MAX(CASE WHEN f.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_first72h,
    MAX(CASE WHEN l.hadm_id IS NOT NULL THEN 1 ELSE 0 END) AS has_final24h
  FROM final_cohort c
  LEFT JOIN (SELECT DISTINCT hadm_id, subject_id, drug_class FROM first72h_drugs) f 
    ON c.hadm_id = f.hadm_id AND c.subject_id = f.subject_id
  LEFT JOIN (SELECT DISTINCT hadm_id, subject_id, drug_class FROM final24h_drugs) l 
    ON c.hadm_id = l.hadm_id AND c.subject_id = l.subject_id
  GROUP BY c.hadm_id, c.subject_id, drug_class
),
final_result AS (
  SELECT 
    drug_class,
    'first72h' AS time_period,
    COUNTIF(has_first72h = 1) * 100.0 / COUNT(*) AS percentage
  FROM patient_class_flags
  GROUP BY drug_class, time_period

  UNION ALL

  SELECT 
    drug_class,
    'final24h' AS time_period,
    COUNTIF(has_final24h = 1) * 100.0 / COUNT(*) AS percentage
  FROM patient_class_flags
  GROUP BY drug_class, time_period
)
SELECT * FROM final_result
ORDER BY drug_class, time_period;