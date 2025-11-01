WITH 
-- Step 1: Identify patients with diabetes and acute HF
cohort AS (
  SELECT DISTINCT p.subject_id, p.gender, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON p.subject_id = diag.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag ON diag.icd_code = d_diag.icd_code AND diag.icd_version = d_diag.icd_version
  WHERE p.gender = 'M' AND p.anchor_age BETWEEN 42 AND 52
  AND d_diag.long_title LIKE '%Diabetes%' 
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag_hf
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_diag_hf ON diag_hf.icd_code = d_diag_hf.icd_code AND diag_hf.icd_version = d_diag_hf.icd_version
    WHERE diag_hf.subject_id = p.subject_id AND d_diag_hf.long_title LIKE '%Heart failure%'
  )
),

-- Step 2: Determine relevant hospital admissions
adm AS (
  SELECT a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN cohort ON a.subject_id = cohort.subject_id
),

-- Step 3: Extract medication data
meds AS (
  SELECT 
    p.hadm_id,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%sulfonylurea%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%dulaglutide%' OR LOWER(p.drug) LIKE '%semaglutide%' THEN 'GLP-1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' THEN 'TZD'
      ELSE NULL
    END AS med_class,
    p.starttime,
    p.stoptime
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN adm ON p.hadm_id = adm.hadm_id
  WHERE p.starttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR)
  OR p.starttime BETWEEN DATETIME_SUB(adm.dischtime, INTERVAL 12 HOUR) AND adm.dischtime
),

-- Calculate prevalence in first 24h and final 12h
prevalence AS (
  SELECT 
    meds.hadm_id,
    med_class,
    CASE 
      WHEN meds.starttime BETWEEN adm.admittime AND DATETIME_ADD(adm.admittime, INTERVAL 24 HOUR) THEN 'First 24h' 
      ELSE 'Final 12h' 
    END AS period,
    COUNT(DISTINCT meds.starttime) > 0 AS med_given
  FROM meds
  INNER JOIN adm ON meds.hadm_id = adm.hadm_id
  GROUP BY meds.hadm_id, med_class, period
)

-- Final calculation
SELECT 
  med_class,
  SUM(CASE WHEN period = 'First 24h' AND med_given THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id) AS prevalence_first_24h,
  SUM(CASE WHEN period = 'Final 12h' AND med_given THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id) AS prevalence_final_12h,
  (SUM(CASE WHEN period = 'Final 12h' AND med_given THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id)) - 
  (SUM(CASE WHEN period = 'First 24h' AND med_given THEN 1 ELSE 0 END) / COUNT(DISTINCT hadm_id)) AS net_change_pp
FROM prevalence
GROUP BY med_class
ORDER BY med_class;