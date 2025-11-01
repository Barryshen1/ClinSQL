WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age,
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 64 AND 74
),

diabetes_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%') 
    OR (icd_version = 10 AND icd_code LIKE 'E11%')
),

acute_hf_codes AS (
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND icd_code IN ('428.21','428.23','428.31','428.33','428.41','428.43'))
    OR (icd_version = 10 AND icd_code IN ('I50.21','I50.23','I50.31','I50.33','I50.41','I50.43','I50.81','I50.83'))
),

cohort_diag AS (
  SELECT DISTINCT c.subject_id, c.hadm_id, c.admittime, c.dischtime
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN diabetes_codes dc 
      ON d.icd_code = dc.icd_code 
      AND d.icd_version = dc.icd_version
    WHERE d.subject_id = c.subject_id 
      AND d.hadm_id = c.hadm_id
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    INNER JOIN acute_hf_codes ac 
      ON d.icd_code = ac.icd_code 
      AND d.icd_version = ac.icd_version
    WHERE d.subject_id = c.subject_id 
      AND d.hadm_id = c.hadm_id
  )
),

antidiabetic_orders AS (
  SELECT 
    subject_id, 
    hadm_id, 
    starttime, 
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' 
        OR LOWER(drug) LIKE '%lispro%' 
        OR LOWER(drug) LIKE '%aspart%' 
        OR LOWER(drug) LIKE '%glargine%' 
        OR LOWER(drug) LIKE '%detemir%' 
        OR LOWER(drug) LIKE '%NPH%' 
        OR LOWER(drug) LIKE '%humulin%' 
        OR LOWER(drug) LIKE '%novolin%' THEN 'insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(drug) LIKE '%glyburide%' 
        OR LOWER(drug) LIKE '%glipizide%' 
        OR LOWER(drug) LIKE '%glimepiride%' THEN 'sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' 
        OR LOWER(drug) LIKE '%saxagliptin%' 
        OR LOWER(drug) LIKE '%linagliptin%' 
        OR LOWER(drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' 
        OR LOWER(drug) LIKE '%dapagliflozin%' 
        OR LOWER(drug) LIKE '%empagliflozin%' THEN 'sglt2'
      WHEN LOWER(drug) LIKE '%exenatide%' 
        OR LOWER(drug) LIKE '%liraglutide%' 
        OR LOWER(drug) LIKE '%dulaglutide%' 
        OR LOWER(drug) LIKE '%semaglutide%' 
        OR LOWER(drug) LIKE '%lixisenatide%' THEN 'glp1'
      WHEN LOWER(drug) LIKE '%pioglitazone%' 
        OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'tzd'
    END AS class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IS NOT NULL
),

class_list AS (
  SELECT 'insulin' AS class UNION ALL
  SELECT 'metformin' UNION ALL
  SELECT 'sulfonylureas' UNION ALL
  SELECT 'dpp4' UNION ALL
  SELECT 'sglt2' UNION ALL
  SELECT 'glp1' UNION ALL
  SELECT 'tzd'
),

patient_class AS (
  SELECT 
    c.subject_id, 
    c.hadm_id, 
    c.admittime, 
    c.dischtime,
    cl.class
  FROM cohort_diag c
  CROSS JOIN class_list cl
),

patient_class_orders AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    pc.class,
    MAX(
      CASE WHEN ao.starttime 
        BETWEEN pc.admittime 
        AND DATETIME_ADD(pc.admittime, INTERVAL 12 HOUR) 
        THEN 1 ELSE 0 END
    ) AS in_first_12h,
    MAX(
      CASE WHEN ao.starttime 
        BETWEEN DATETIME_SUB(pc.dischtime, INTERVAL 48 HOUR) 
        AND pc.dischtime 
        THEN 1 ELSE 0 END
    ) AS in_final_48h
  FROM patient_class pc
  LEFT JOIN antidiabetic_orders ao
    ON pc.subject_id = ao.subject_id
    AND pc.hadm_id = ao.hadm_id
    AND pc.class = ao.class
  GROUP BY pc.subject_id, pc.hadm_id, pc.class
),

totals AS (
  SELECT COUNT(*) AS total_patients
  FROM cohort_diag
)

SELECT 
  pco.class,
  SUM(pco.in_first_12h) AS count_first_12h,
  ROUND(SUM(pco.in_first_12h) * 100.0 / t.total_patients, 2) AS pct_first_12h,
  SUM(pco.in_final_48h) AS count_final_48h,
  ROUND(SUM(pco.in_final_48h) * 100.0 / t.total_patients, 2) AS pct_final_48h
FROM patient_class_orders pco
CROSS JOIN totals t
GROUP BY pco.class, t.total_patients
ORDER BY pco.class;