WITH cohort AS (
  -- Base admissions for age/gender
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 42 AND 52
    AND p.gender = 'M'
    AND a.admittime >= '2008-01-01'
    AND (a.hospital_expire_flag = 0 OR a.deathtime > TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY))
),

diabetes AS (
  -- Diabetes diagnoses (ICD-10: E10.*, E11.*, E13.*)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = '10'
    AND (icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%')
),

hf AS (
  -- Acute HF (ICD-10: I50.*)
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = '10'
    AND icd_code LIKE 'I50%'
),

patient_cohort AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.admittime,
    c.dischtime
  FROM cohort c
  INNER JOIN diabetes d ON c.subject_id = d.subject_id AND c.hadm_id = d.hadm_id
  INNER JOIN hf h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
),

-- Drug exposure in first 24h
first_24h_drugs AS (
  SELECT DISTINCT
    pc.hadm_id,
    CASE 
      WHEN pr.drug LIKE '%INSULIN%' THEN 'Insulin'
      WHEN pr.drug IN ('METFORMIN', 'METFORMIN HYDROCHLORIDE') OR pr.drug LIKE '%METFORMIN%' THEN 'Metformin'
      WHEN pr.drug IN ('GLIPIZIDE', 'GLYBURIDE', 'GLIMEPIRIDE') OR pr.drug LIKE '%SULFONYLUREA%' THEN 'Sulfonylurea'
      WHEN pr.drug IN ('SITAGLIPTIN', 'LINAGLIPTIN', 'SAXAGLIPTIN') OR pr.drug LIKE '%DPP-4%' OR pr.drug LIKE '%GLIPTIN%' THEN 'DPP-4'
      WHEN pr.drug IN ('DAPAGLIFLOZIN', 'EMPAGLIFLOZIN', 'CANAFLIFLOZIN') OR pr.drug LIKE '%SGLT2%' OR pr.drug LIKE '%GLIFLOZIN%' THEN 'SGLT2'
      WHEN pr.drug IN ('LIRAGLUTIDE', 'SEMAGLUTIDE', 'DULAGLUTIDE', 'EXENATIDE') OR pr.drug LIKE '%GLP-1%' OR pr.drug LIKE '%TIDE%' THEN 'GLP-1'
      WHEN pr.drug IN ('PIOGLITAZONE', 'ROSIGLITAZONE') OR pr.drug LIKE '%THIAZOLIDINEDIONE%' OR pr.drug LIKE '%GLITAZONE%' THEN 'TZD'
    END AS drug_class
  FROM patient_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pc.subject_id = pr.subject_id 
    AND CAST(pc.hadm_id AS STRING) = pr.hadm_id
    AND pr.starttime >= pc.admittime
    AND pr.starttime <= TIMESTAMP_ADD(pc.admittime, INTERVAL 1 DAY)
    AND pr.drug IS NOT NULL
    AND pr.drug != ''
  WHERE drug_class IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT
    pc.hadm_id,
    CASE 
      WHEN py.medication LIKE '%INSULIN%' THEN 'Insulin'
      WHEN py.medication IN ('METFORMIN', 'METFORMIN HYDROCHLORIDE') OR py.medication LIKE '%METFORMIN%' THEN 'Metformin'
      WHEN py.medication IN ('GLIPIZIDE', 'GLYBURIDE', 'GLIMEPIRIDE') OR py.medication LIKE '%SULFONYLUREA%' THEN 'Sulfonylurea'
      WHEN py.medication IN ('SITAGLIPTIN', 'LINAGLIPTIN', 'SAXAGLIPTIN') OR py.medication LIKE '%DPP-4%' OR py.medication LIKE '%GLIPTIN%' THEN 'DPP-4'
      WHEN py.medication IN ('DAPAGLIFLOZIN', 'EMPAGLIFLOZIN', 'CANAFLIFLOZIN') OR py.medication LIKE '%SGLT2%' OR py.medication LIKE '%GLIFLOZIN%' THEN 'SGLT2'
      WHEN py.medication IN ('LIRAGLUTIDE', 'SEMAGLUTIDE', 'DULAGLUTIDE', 'EXENATIDE') OR py.medication LIKE '%GLP-1%' OR py.medication LIKE '%TIDE%' THEN 'GLP-1'
      WHEN py.medication IN ('PIOGLITAZONE', 'ROSIGLITAZONE') OR py.medication LIKE '%THIAZOLIDINEDIONE%' OR py.medication LIKE '%GLITAZONE%' THEN 'TZD'
    END AS drug_class
  FROM patient_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` py
    ON pc.subject_id = py.subject_id 
    AND CAST(pc.hadm_id AS STRING) = py.hadm_id
    AND COALESCE(py.starttime, py.entertime) >= pc.admittime
    AND COALESCE(py.starttime, py.entertime) <= TIMESTAMP_ADD(pc.admittime, INTERVAL 1 DAY)
    AND py.medication IS NOT NULL
    AND py.medication != ''
  WHERE drug_class IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT
    pc.hadm_id,
    CASE 
      WHEN di.label LIKE '%INSULIN%' THEN 'Insulin'
      ELSE NULL
    END AS drug_class
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON pc.subject_id = ie.subject_id 
    AND CAST(pc.hadm_id AS STRING) = ie.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime >= pc.admittime
    AND ie.starttime <= TIMESTAMP_ADD(pc.admittime, INTERVAL 1 DAY)
    AND di.label LIKE '%INSULIN%'
    AND drug_class IS NOT NULL
),

-- Drug exposure in final 12h
final_12h_drugs AS (
  -- Similar structure to first_24h_drugs, but for final 12h
  SELECT DISTINCT
    pc.hadm_id,
    CASE 
      WHEN pr.drug LIKE '%INSULIN%' THEN 'Insulin'
      WHEN pr.drug IN ('METFORMIN', 'METFORMIN HYDROCHLORIDE') OR pr.drug LIKE '%METFORMIN%' THEN 'Metformin'
      WHEN pr.drug IN ('GLIPIZIDE', 'GLYBURIDE', 'GLIMEPIRIDE') OR pr.drug LIKE '%SULFONYLUREA%' THEN 'Sulfonylurea'
      WHEN pr.drug IN ('SITAGLIPTIN', 'LINAGLIPTIN', 'SAXAGLIPTIN') OR pr.drug LIKE '%DPP-4%' OR pr.drug LIKE '%GLIPTIN%' THEN 'DPP-4'
      WHEN pr.drug IN ('DAPAGLIFLOZIN', 'EMPAGLIFLOZIN', 'CANAFLIFLOZIN') OR pr.drug LIKE '%SGLT2%' OR pr.drug LIKE '%GLIFLOZIN%' THEN 'SGLT2'
      WHEN pr.drug IN ('LIRAGLUTIDE', 'SEMAGLUTIDE', 'DULAGLUTIDE', 'EXENATIDE') OR pr.drug LIKE '%GLP-1%' OR pr.drug LIKE '%TIDE%' THEN 'GLP-1'
      WHEN pr.drug IN ('PIOGLITAZONE', 'ROSIGLITAZONE') OR pr.drug LIKE '%THIAZOLIDINEDIONE%' OR pr.drug LIKE '%GLITAZONE%' THEN 'TZD'
    END AS drug_class
  FROM patient_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pc.subject_id = pr.subject_id 
    AND CAST(pc.hadm_id AS STRING) = pr.hadm_id
    AND pr.starttime >= TIMESTAMP_SUB(pc.dischtime, INTERVAL 12 HOUR)
    AND pr.starttime <= pc.dischtime
    AND pr.drug IS NOT NULL
    AND pr.drug != ''
  WHERE drug_class IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT
    pc.hadm_id,
    CASE 
      WHEN py.medication LIKE '%INSULIN%' THEN 'Insulin'
      WHEN py.medication IN ('METFORMIN', 'METFORMIN HYDROCHLORIDE') OR py.medication LIKE '%METFORMIN%' THEN 'Metformin'
      WHEN py.medication IN ('GLIPIZIDE', 'GLYBURIDE', 'GLIMEPIRIDE') OR py.medication LIKE '%SULFONYLUREA%' THEN 'Sulfonylurea'
      WHEN py.medication IN ('SITAGLIPTIN', 'LINAGLIPTIN', 'SAXAGLIPTIN') OR py.medication LIKE '%DPP-4%' OR py.medication LIKE '%GLIPTIN%' THEN 'DPP-4'
      WHEN py.medication IN ('DAPAGLIFLOZIN', 'EMPAGLIFLOZIN', 'CANAFLIFLOZIN') OR py.medication LIKE '%SGLT2%' OR py.medication LIKE '%GLIFLOZIN%' THEN 'SGLT2'
      WHEN py.medication IN ('LIRAGLUTIDE', 'SEMAGLUTIDE', 'DULAGLUTIDE', 'EXENATIDE') OR py.medication LIKE '%GLP-1%' OR py.medication LIKE '%TIDE%' THEN 'GLP-1'
      WHEN py.medication IN ('PIOGLITAZONE', 'ROSIGLITAZONE') OR py.medication LIKE '%THIAZOLIDINEDIONE%' OR py.medication LIKE '%GLITAZONE%' THEN 'TZD'
    END AS drug_class
  FROM patient_cohort pc
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.pharmacy` py
    ON pc.subject_id = py.subject_id 
    AND CAST(pc.hadm_id AS STRING) = py.hadm_id
    AND COALESCE(py.starttime, py.entertime) >= TIMESTAMP_SUB(pc.dischtime, INTERVAL 12 HOUR)
    AND COALESCE(py.starttime, py.entertime) <= pc.dischtime
    AND py.medication IS NOT NULL
    AND py.medication != ''
  WHERE drug_class IS NOT NULL

  UNION DISTINCT

  SELECT DISTINCT
    pc.hadm_id,
    CASE 
      WHEN di.label LIKE '%INSULIN%' THEN 'Insulin'
      ELSE NULL
    END AS drug_class
  FROM patient_cohort pc
  INNER JOIN `physionet-data.mimiciv_3_1_icu.inputevents` ie
    ON pc.subject_id = ie.subject_id 
    AND CAST(pc.hadm_id AS STRING) = ie.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ie.itemid = di.itemid
  WHERE ie.starttime >= TIMESTAMP_SUB(pc.dischtime, INTERVAL 12 HOUR)
    AND ie.starttime <= pc.dischtime
    AND di.label LIKE '%INSULIN%'
    AND drug_class IS NOT NULL
),

-- Aggregate exposures
drug_summary AS (
  SELECT 
    'Insulin' AS drug_class, 
    COUNT(DISTINCT CASE WHEN f24.hadm_id IS NOT NULL THEN f24.hadm_id END) AS exposed_first_24h,
    COUNT(DISTINCT CASE WHEN f12.hadm_id IS NOT NULL THEN f12.hadm_id END) AS exposed_final_12h
  FROM patient_cohort pc
  LEFT JOIN first_24h_drugs f24 ON pc.hadm_id = f24.hadm_id AND f24.drug_class = 'Insulin'
  LEFT JOIN final_12h_drugs f12 ON pc.hadm_id = f12.hadm_id AND f12.drug_class = 'Insulin'

  UNION ALL

  SELECT 
    'Metformin' AS drug_class, 
    COUNT(DISTINCT CASE WHEN f24.hadm_id IS NOT NULL THEN f24.hadm_id END) AS exposed_first_24h,
    COUNT(DISTINCT CASE WHEN f12.hadm_id IS NOT NULL THEN f12.hadm_id END) AS exposed_final_12h
  FROM patient_cohort pc
  LEFT JOIN first_24h_drugs f24 ON pc.hadm_id = f24.hadm_id AND f24.drug_class = 'Metformin'
  LEFT JOIN final_12h_drugs f12 ON pc.hadm_id = f12.hadm_id AND f12.drug_class = 'Metformin'

  UNION ALL

  SELECT 
    'Sulfonylurea' AS drug_class, 
    COUNT(DISTINCT CASE WHEN f24.hadm_id IS NOT NULL THEN f24.hadm_id END) AS exposed_first_24h,
    COUNT(DISTINCT CASE WHEN f12.hadm_id IS NOT NULL THEN f12.hadm_id END) AS exposed_final_12h
  FROM patient_cohort pc
  LEFT JOIN first_24h_drugs f24 ON pc.hadm_id = f24.hadm_id AND f24.drug_class = 'Sulfonylurea'
  LEFT JOIN final_12h_drugs f12 ON pc.hadm_id = f12.hadm_id AND f12.drug_class = 'Sulfonylurea'

  UNION ALL

  SELECT 
    'DPP-4' AS drug_class, 
    COUNT(DISTINCT CASE WHEN f24.hadm_id IS NOT NULL THEN f24.hadm_id END) AS exposed_first_24h,
    COUNT(DISTINCT CASE WHEN f12.hadm_id IS NOT NULL THEN f12.hadm_id END) AS exposed_final_12h
  FROM patient_cohort pc
  LEFT JOIN first_24h_drugs f24 ON pc.hadm_id = f24.hadm_id AND f24.drug_class = 'DPP-4'
  LEFT JOIN final_12h_drugs f12 ON pc.hadm_id = f12.hadm_id AND f12.drug_class = 'DPP-4'

  UNION ALL

  SELECT 
    'SGLT2' AS drug_class, 
    COUNT(DISTINCT CASE WHEN f24.hadm_id IS NOT NULL THEN f24.hadm_id END) AS exposed_first_24h,
    COUNT(DISTINCT CASE WHEN f12.hadm_id IS NOT NULL THEN f12.hadm_id END) AS exposed_final_12h
  FROM patient_cohort pc
  LEFT JOIN first_24h_drugs f24 ON pc.hadm_id = f24.hadm_id AND f24.drug_class = 'SGLT2'
  LEFT JOIN final_12h_drugs f12 ON pc.hadm_id = f12.hadm_id AND f12.drug_class = 'SGLT2'

  UNION ALL

  SELECT 
    'GLP-1' AS drug_class, 
    COUNT(DISTINCT CASE WHEN f24.hadm_id IS NOT NULL THEN f24.hadm_id END) AS exposed_first_24h,
    COUNT(DISTINCT CASE WHEN f12.hadm_id IS NOT NULL THEN f12.hadm_id END) AS exposed_final_12h
  FROM patient_cohort pc
  LEFT JOIN first_24h_drugs f24 ON pc.hadm_id = f24.hadm_id AND f24.drug_class = 'GLP-1'
  LEFT JOIN final_12h_drugs f12 ON pc.hadm_id = f12.hadm_id AND f12.drug_class = 'GLP-1'

  UNION ALL

  SELECT 
    'TZD' AS drug_class, 
    COUNT(DISTINCT CASE WHEN f24.hadm_id IS NOT NULL THEN f24.hadm_id END) AS exposed_first_24h,
    COUNT(DISTINCT CASE WHEN f12.hadm_id IS NOT NULL THEN f12.hadm_id END) AS exposed_final_12h
  FROM patient_cohort pc
  LEFT JOIN first_24h_drugs f24 ON pc.hadm_id = f24.hadm_id AND f24.drug_class = 'TZD'
  LEFT JOIN final_12h_drugs f12 ON pc.hadm_id = f12.hadm_id AND f12.drug_class = 'TZD'
)

-- Final metrics
SELECT 
  drug_class,
  ROUND((exposed_first_24h / (SELECT COUNT(*) FROM patient_cohort)) * 100, 2) AS first_24h_pct,
  ROUND((exposed_final_12h / (SELECT COUNT(*) FROM patient_cohort)) * 100, 2) AS final_12h_pct,
  ROUND(((exposed_final_12h - exposed_first_24h) / (SELECT COUNT(*) FROM patient_cohort)) * 100, 2) AS net_change_pp
FROM drug_summary
ORDER BY 
  CASE drug_class
    WHEN 'Insulin' THEN 1
    WHEN 'Metformin' THEN 2
    WHEN 'Sulfonylurea' THEN 3
    WHEN 'DPP-4' THEN 4
    WHEN 'SGLT2' THEN 5
    WHEN 'GLP-1' THEN 6
    WHEN 'TZD' THEN 7
  END;