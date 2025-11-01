WITH
-- 1. Get diabetes and acute heart failure ICD codes
diabetes_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code LIKE '250%')
    OR (icd_version = 10 AND (
      icd_code LIKE 'E10%' OR
      icd_code LIKE 'E11%' OR
      icd_code LIKE 'E13%' OR
      icd_code LIKE 'E14%'
    ))
),
acute_hf_icd AS (
  SELECT DISTINCT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE
    (icd_version = 9 AND icd_code IN ('42821','42823','42831','42833','42841','42843'))
    OR (icd_version = 10 AND icd_code IN (
      'I5021','I5023','I5031','I5033','I5041','I5043','I50811','I50813'
    ))
),
-- 2. Admissions with diabetes
adm_diabetes AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN diabetes_icd icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
),
-- 3. Admissions with acute heart failure
adm_acute_hf AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN acute_hf_icd icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
),
-- 4. Eligible admissions: male, age 71-81, both diabetes and acute HF
eligible_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND a.hadm_id IN (SELECT hadm_id FROM adm_diabetes)
    AND a.hadm_id IN (SELECT hadm_id FROM adm_acute_hf)
),
-- 5. Drug class mapping
drug_class_map AS (
  SELECT 'Metformin' AS drug_class, 'metformin' AS drug_name
  UNION ALL SELECT 'Sulfonylureas', 'glipizide'
  UNION ALL SELECT 'Sulfonylureas', 'glyburide'
  UNION ALL SELECT 'Sulfonylureas', 'glimepiride'
  UNION ALL SELECT 'Sulfonylureas', 'tolbutamide'
  UNION ALL SELECT 'Sulfonylureas', 'chlorpropamide'
  UNION ALL SELECT 'DPP-4', 'sitagliptin'
  UNION ALL SELECT 'DPP-4', 'saxagliptin'
  UNION ALL SELECT 'DPP-4', 'linagliptin'
  UNION ALL SELECT 'DPP-4', 'alogliptin'
  UNION ALL SELECT 'SGLT2', 'canagliflozin'
  UNION ALL SELECT 'SGLT2', 'dapagliflozin'
  UNION ALL SELECT 'SGLT2', 'empagliflozin'
  UNION ALL SELECT 'SGLT2', 'ertugliflozin'
  UNION ALL SELECT 'Thiazolidinediones', 'pioglitazone'
  UNION ALL SELECT 'Thiazolidinediones', 'rosiglitazone'
),
-- 6. First prescription per drug class per admission
drug_initiation AS (
  SELECT
    ea.hadm_id,
    ea.subject_id,
    dc.drug_class,
    MIN(pr.starttime) AS first_starttime,
    ea.admittime,
    ea.dischtime
  FROM eligible_admissions ea
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON ea.hadm_id = pr.hadm_id
  JOIN drug_class_map dc
    ON LOWER(pr.drug) LIKE CONCAT('%', dc.drug_name, '%')
  GROUP BY ea.hadm_id, ea.subject_id, dc.drug_class, ea.admittime, ea.dischtime
),
-- 7. Initiation timing flags
drug_initiation_timing AS (
  SELECT
    drug_class,
    hadm_id,
    subject_id,
    first_starttime,
    admittime,
    dischtime,
    TIMESTAMP_DIFF(first_starttime, admittime, HOUR) AS hours_from_admit,
    TIMESTAMP_DIFF(dischtime, first_starttime, HOUR) AS hours_before_discharge,
    CASE WHEN TIMESTAMP_DIFF(first_starttime, admittime, HOUR) <= 72 THEN 1 ELSE 0 END AS init_72h,
    CASE WHEN TIMESTAMP_DIFF(dischtime, first_starttime, HOUR) <= 48 THEN 1 ELSE 0 END AS init_last48h
  FROM drug_initiation
),
-- 8. Aggregate rates
rates AS (
  SELECT
    dc.drug_class,
    COUNT(DISTINCT ea.hadm_id) AS n_admissions,
    COUNT(DISTINCT CASE WHEN dit.init_72h = 1 THEN dit.hadm_id END) AS n_init_72h,
    COUNT(DISTINCT CASE WHEN dit.init_last48h = 1 THEN dit.hadm_id END) AS n_init_last48h,
    SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN dit.init_72h = 1 THEN dit.hadm_id END), COUNT(DISTINCT ea.hadm_id)) * 100 AS rate_72h_pct,
    SAFE_DIVIDE(COUNT(DISTINCT CASE WHEN dit.init_last48h = 1 THEN dit.hadm_id END), COUNT(DISTINCT ea.hadm_id)) * 100 AS rate_last48h_pct
  FROM drug_class_map dc
  LEFT JOIN eligible_admissions ea
    ON TRUE
  LEFT JOIN drug_initiation_timing dit
    ON ea.hadm_id = dit.hadm_id AND dc.drug_class = dit.drug_class
  GROUP BY dc.drug_class
)
SELECT
  drug_class,
  n_admissions,
  n_init_72h,
  rate_72h_pct,
  n_init_last48h,
  rate_last48h_pct
FROM rates
ORDER BY drug_class;