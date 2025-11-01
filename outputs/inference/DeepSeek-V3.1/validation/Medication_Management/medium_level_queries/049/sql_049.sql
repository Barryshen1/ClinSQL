WITH cohort AS (
  -- Get eligible admissions: male, age 66-76, with diabetes and heart failure, LOS>=72h
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime, adm.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 66 AND 76
    AND DATETIME_DIFF(adm.dischtime, adm.admittime, HOUR) >= 72
    AND adm.hadm_id IN (
      -- Admissions with diabetes
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'E1%' AND icd_version = 10
      INTERSECT DISTINCT
      -- Admissions with heart failure
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE icd_code LIKE 'I50%' AND icd_version = 10
    )
),

-- Custom mapping of antidiabetic drugs to classes
antidiabetic_classes AS (
  SELECT
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' THEN 'DPP-4 inhibitor'
      WHEN LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%semaglutide%' THEN 'GLP-1 agonist'
      ELSE 'Other antidiabetic'
    END AS drug_class
  FROM (
    SELECT DISTINCT drug FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%insulin%' 
       OR LOWER(drug) LIKE '%metformin%'
       OR LOWER(drug) LIKE '%glipizide%'
       OR LOWER(drug) LIKE '%glyburide%'
       OR LOWER(drug) LIKE '%glimepiride%'
       OR LOWER(drug) LIKE '%sitagliptin%'
       OR LOWER(drug) LIKE '%saxagliptin%'
       OR LOWER(drug) LIKE '%linagliptin%'
       OR LOWER(drug) LIKE '%empagliflozin%'
       OR LOWER(drug) LIKE '%canagliflozin%'
       OR LOWER(drug) LIKE '%dapagliflozin%'
       OR LOWER(drug) LIKE '%liraglutide%'
       OR LOWER(drug) LIKE '%dulaglutide%'
       OR LOWER(drug) LIKE '%semaglutide%'
  )
),

-- Prescriptions in first 72h
first_72h AS (
  SELECT DISTINCT
    c.hadm_id,
    ac.drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  INNER JOIN antidiabetic_classes ac
    ON rx.drug = ac.drug
  WHERE rx.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 72 HOUR)
),

-- Prescriptions in final 24h
final_24h AS (
  SELECT DISTINCT
    c.hadm_id,
    ac.drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` rx
    ON c.hadm_id = rx.hadm_id
  INNER JOIN antidiabetic_classes ac
    ON rx.drug = ac.drug
  WHERE rx.starttime BETWEEN DATETIME_SUB(c.dischtime, INTERVAL 24 HOUR) AND c.dischtime
)

-- Calculate percentages per class for each time window
SELECT
  'First 72h' AS time_window,
  drug_class,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(100.0 * COUNT(DISTINCT hadm_id) / (SELECT COUNT(*) FROM cohort), 2) AS percentage
FROM first_72h
GROUP BY drug_class

UNION ALL

SELECT
  'Final 24h' AS time_window,
  drug_class,
  COUNT(DISTINCT hadm_id) AS admission_count,
  ROUND(100.0 * COUNT(DISTINCT hadm_id) / (SELECT COUNT(*) FROM cohort), 2) AS percentage
FROM final_24h
GROUP BY drug_class

ORDER BY time_window, admission_count DESC;