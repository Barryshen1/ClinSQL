WITH cohort AS (
  SELECT 
    a.hadm_id, 
    a.subject_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 66 AND 76
    AND a.dischtime - a.admittime >= INTERVAL '72' HOUR
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '250.%')
          OR (d.icd_version = 10 AND d.icd_code BETWEEN 'E10' AND 'E14')
        )
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428.%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
),
prescriptions_with_class AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    c.admittime,
    c.dischtime,
    CASE
      WHEN p.drug LIKE '%insulin%' THEN 'Insulin'
      WHEN p.drug LIKE '%metformin%' THEN 'Metformin'
      WHEN p.drug LIKE '%glipizide%' OR p.drug LIKE '%glyburide%' OR p.drug LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%alogliptin%' OR p.drug LIKE '%saxagliptin%' THEN 'DPP-4 inhibitors'
      WHEN p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' THEN 'SGLT2 inhibitors'
      WHEN p.drug LIKE '%exenatide%' OR p.drug LIKE '%liraglutide%' OR p.drug LIKE '%semaglutide%' THEN 'GLP-1 agonists'
      WHEN p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
      ELSE 'Other'
    END AS antidiabetic_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE p.drug IS NOT NULL
),
first_72h AS (
  SELECT
    subject_id,
    antidiabetic_class,
    MAX(CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL '72' HOUR THEN 1 ELSE 0 END) AS in_first_72h
  FROM prescriptions_with_class
  GROUP BY subject_id, antidiabetic_class
),
final_24h AS (
  SELECT
    subject_id,
    antidiabetic_class,
    MAX(CASE WHEN starttime BETWEEN dischtime - INTERVAL '24' HOUR AND dischtime THEN 1 ELSE 0 END) AS in_final_24h
  FROM prescriptions_with_class
  GROUP BY subject_id, antidiabetic_class
),
class_counts AS (
  SELECT
    f.antidiabetic_class,
    ROUND(AVG(f.in_first_72h) * 100, 2) AS first_72h_pct,
    ROUND(AVG(final.in_final_24h) * 100, 2) AS final_24h_pct
  FROM first_72h f
  JOIN final_24h final 
    ON f.subject_id = final.subject_id 
    AND f.antidiabetic_class = final.antidiabetic_class
  GROUP BY f.antidiabetic_class
)
SELECT * FROM class_counts;