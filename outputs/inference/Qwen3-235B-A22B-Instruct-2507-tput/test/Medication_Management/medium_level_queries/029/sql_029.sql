WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 69 AND 79
),
t2dm_hf_admissions AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (LOWER(d.long_title) LIKE '%diabetes mellitus type 2%'
     OR d.icd_code LIKE 'E11%')
  INTERSECT
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE (LOWER(d.long_title) LIKE '%heart failure%'
     OR d.icd_code LIKE 'I50%')
),
cohort_admissions AS (
  SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patient_cohort pc ON a.subject_id = pc.subject_id
  INNER JOIN t2dm_hf_admissions th ON a.hadm_id = th.hadm_id
),
drug_exposure AS (
  SELECT 
    ca.subject_id,
    -- Check if drug overlaps with first 72 hours [admittime, admittime + 3 DAYS]
    MAX(CASE WHEN pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 3 DAY)
              AND (pr.stoptime IS NULL OR pr.stoptime >= ca.admittime)
              AND (LOWER(pr.drug) LIKE '%insulin%' 
                   OR LOWER(pr.gsn) LIKE '%insulin%' 
                   OR LOWER(pr.drug) IN ('lantus', 'levemir', 'humalog', 'novolog', 'apidra', 'basaglar'))
         THEN 1 ELSE 0 END) AS insulin_first_72h,
    MAX(CASE WHEN pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 3 DAY)
              AND (pr.stoptime IS NULL OR pr.stoptime >= ca.admittime)
              AND (LOWER(pr.drug) LIKE '%metform%' 
                   OR LOWER(pr.gsn) LIKE '%metform%')
         THEN 1 ELSE 0 END) AS metformin_first_72h,
    MAX(CASE WHEN pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 3 DAY)
              AND (pr.stoptime IS NULL OR pr.stoptime >= ca.admittime)
              AND (LOWER(pr.drug) LIKE '%glyburide%'
                   OR LOWER(pr.drug) LIKE '%glipizide%'
                   OR LOWER(pr.drug) LIKE '%glimiperide%'
                   OR LOWER(pr.gsn) LIKE '%glyburide%'
                   OR LOWER(pr.gsn) LIKE '%glipizide%'
                   OR LOWER(pr.gsn) LIKE '%glimiperide%')
         THEN 1 ELSE 0 END) AS sulfonylurea_first_72h,
    MAX(CASE WHEN pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 3 DAY)
              AND (pr.stoptime IS NULL OR pr.stoptime >= ca.admittime)
              AND (LOWER(pr.drug) LIKE '%sitagliptin%'
                   OR LOWER(pr.drug) LIKE '%saxagliptin%'
                   OR LOWER(pr.drug) LIKE '%linagliptin%'
                   OR LOWER(pr.drug) LIKE '%alogliptin%'
                   OR LOWER(pr.gsn) LIKE '%sitagliptin%'
                   OR LOWER(pr.gsn) LIKE '%saxagliptin%'
                   OR LOWER(pr.gsn) LIKE '%linagliptin%'
                   OR LOWER(pr.gsn) LIKE '%alogliptin%')
         THEN 1 ELSE 0 END) AS dpp4_first_72h,
    MAX(CASE WHEN pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 3 DAY)
              AND (pr.stoptime IS NULL OR pr.stoptime >= ca.admittime)
              AND (LOWER(pr.drug) LIKE '%empagliflozin%'
                   OR LOWER(pr.drug) LIKE '%canagliflozin%'
                   OR LOWER(pr.drug) LIKE '%dapagliflozin%'
                   OR LOWER(pr.drug) LIKE '%ertugliflozin%'
                   OR LOWER(pr.gsn) LIKE '%empagliflozin%'
                   OR LOWER(pr.gsn) LIKE '%canagliflozin%'
                   OR LOWER(pr.gsn) LIKE '%dapagliflozin%'
                   OR LOWER(pr.gsn) LIKE '%ertugliflozin%')
         THEN 1 ELSE 0 END) AS sglt2_first_72h,
    MAX(CASE WHEN pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 3 DAY)
              AND (pr.stoptime IS NULL OR pr.stoptime >= ca.admittime)
              AND (LOWER(pr.drug) LIKE '%liraglutide%'
                   OR LOWER(pr.drug) LIKE '%dulaglutide%'
                   OR LOWER(pr.drug) LIKE '%semaglutide%'
                   OR LOWER(pr.drug) LIKE '%exenatide%'
                   OR LOWER(pr.gsn) LIKE '%liraglutide%'
                   OR LOWER(pr.gsn) LIKE '%dulaglutide%'
                   OR LOWER(pr.gsn) LIKE '%semaglutide%'
                   OR LOWER(pr.gsn) LIKE '%exenatide%')
         THEN 1 ELSE 0 END) AS glp1_first_72h,
    MAX(CASE WHEN pr.starttime <= DATETIME_ADD(ca.admittime, INTERVAL 3 DAY)
              AND (pr.stoptime IS NULL OR pr.stoptime >= ca.admittime)
              AND (LOWER(pr.drug) LIKE '%pioglitazone%'
                   OR LOWER(pr.drug) LIKE '%rosiglitazone%'
                   OR LOWER(pr.gsn) LIKE '%pioglitazone%'
                   OR LOWER(pr.gsn) LIKE '%rosiglitazone%')
         THEN 1 ELSE 0 END) AS tzd_first_72h,
    -- Check if drug overlaps with last 72 hours [dischtime - 3 DAYS, dischtime]
    MAX(CASE WHEN pr.starttime <= ca.dischtime
              AND (pr.stoptime IS NULL OR pr.stoptime >= DATETIME_SUB(ca.dischtime, INTERVAL 3 DAY))
              AND (LOWER(pr.drug) LIKE '%insulin%' 
                   OR LOWER(pr.gsn) LIKE '%insulin%' 
                   OR LOWER(pr.drug) IN ('lantus', 'levemir', 'humalog', 'novolog', 'apidra', 'basaglar'))
         THEN 1 ELSE 0 END) AS insulin_last_72h,
    MAX(CASE WHEN pr.starttime <= ca.dischtime
              AND (pr.stoptime IS NULL OR pr.stoptime >= DATETIME_SUB(ca.dischtime, INTERVAL 3 DAY))
              AND (LOWER(pr.drug) LIKE '%metform%' 
                   OR LOWER(pr;