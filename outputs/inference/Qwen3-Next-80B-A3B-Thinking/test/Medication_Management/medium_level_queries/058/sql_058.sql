WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'E11%'
    )
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'I50%'
    )
),
prescriptions_with_class AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    CASE
      WHEN p.drug LIKE '%insulin%' THEN 'Insulin'
      WHEN p.drug LIKE '%metformin%' THEN 'Biguanide'
      WHEN p.drug LIKE '%glipizide%' OR p.drug LIKE '%glyburide%' OR p.drug LIKE '%gliclazide%' THEN 'Sulfonylurea'
      WHEN p.drug LIKE '%sitagliptin%' OR p.drug LIKE '%saxagliptin%' OR p.drug LIKE '%linagliptin%' OR p.drug LIKE '%alogliptin%' THEN 'DPP-4 inhibitor'
      WHEN p.drug LIKE '%empagliflozin%' OR p.drug LIKE '%canagliflozin%' OR p.drug LIKE '%dapagliflozin%' THEN 'SGLT2 inhibitor'
      WHEN p.drug LIKE '%pioglitazone%' OR p.drug LIKE '%rosiglitazone%' THEN 'Thiazolidinedione'
      WHEN p.drug LIKE '%repaglinide%' OR p.drug LIKE '%nateglinide%' THEN 'Meglitinide'
      WHEN p.drug LIKE '%exenatide%' OR p.drug LIKE '%liraglutide%' OR p.drug LIKE '%dulaglutide%' OR p.drug LIKE '%semaglutide%' THEN 'GLP-1 agonist'
      ELSE 'Other'
    END AS antidiabetic_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c 
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  WHERE 
    p.starttime IS NOT NULL
    AND p.drug IS NOT NULL
    AND (
      p.drug LIKE '%insulin%' OR
      p.drug LIKE '%metformin%' OR
      p.drug LIKE '%glipizide%' OR
      p.drug LIKE '%glyburide%' OR
      p.drug LIKE '%gliclazide%' OR
      p.drug LIKE '%sitagliptin%' OR
      p.drug LIKE '%saxagliptin%' OR
      p.drug LIKE '%linagliptin%' OR
      p.drug LIKE '%alogliptin%' OR
      p.drug LIKE '%empagliflozin%' OR
      p.drug LIKE '%canagliflozin%' OR
      p.drug LIKE '%dapagliflozin%' OR
      p.drug LIKE '%pioglitazone%' OR
      p.drug LIKE '%rosiglitazone%' OR
      p.drug LIKE '%repaglinide%' OR
      p.drug LIKE '%nateglinide%' OR
      p.drug LIKE '%exenatide%' OR
      p.drug LIKE '%liraglutide%' OR
      p.drug LIKE '%dulaglutide%' OR
      p.drug LIKE '%semaglutide%'
    )
),
patient_class_periods AS (
  SELECT
    p.subject_id,
    p.antidiabetic_class,
    MAX(CASE WHEN p.starttime BETWEEN c.admittime AND c.admittime + INTERVAL '12' HOUR THEN 1 ELSE 0 END) AS first_12h,
    MAX(CASE WHEN p.starttime BETWEEN c.dischtime - INTERVAL '48' HOUR AND c.dischtime THEN 1 ELSE 0 END) AS final_48h
  FROM prescriptions_with_class p
  JOIN cohort c 
    ON p.subject_id = c.subject_id AND p.hadm_id = c.hadm_id
  GROUP BY p.subject_id, p.antidiabetic_class
)
SELECT
  antidiabetic_class,
  AVG(first_12h) * 100 AS first_12h_rate,
  AVG(final_48h) * 100 AS final_48h_rate,
  (AVG(final_48h) - AVG(first_12h)) * 100 AS net_change_pp
FROM patient_class_periods
GROUP BY antidiabetic_class;