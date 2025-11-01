with `END)` and separated by commas.

sql
WITH diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%diabetes%'
    AND icd_version = 10
    AND (icd_code LIKE 'E11%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'O24.4%' OR icd_code LIKE 'E08%' OR icd_code LIKE 'E09%')
),
hf_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE LOWER(long_title) LIKE '%heart failure%'
    AND icd_version = 10
    AND icd_code LIKE 'I50%'
),
cohort AS (
  SELECT a.hadm_id, a.admittime, a.dischtime, p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 36 AND 46
    AND p.anchor_year >= EXTRACT(YEAR FROM a.admittime)
    AND (p.anchor_year - p.anchor_age) BETWEEN (EXTRACT(YEAR FROM a.admittime) - 46) AND (EXTRACT(YEAR FROM a.admittime) - 36)
),
cohort_with_dx AS (
  SELECT c.*
  FROM cohort c
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    INNER JOIN diabetes_codes dc ON dx.icd_code = dc.icd_code AND dx.icd_version = 10
    WHERE dx.hadm_id = c.hadm_id
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    INNER JOIN hf_codes hf ON dx.icd_code = hf.icd_code AND dx.icd_version = 10
    WHERE dx.hadm_id = c.hadm_id
  )
),
drug_exposure AS (
  SELECT 
    c.hadm_id,
    -- Antidiabetic classes
    (LOWER(p.drug) LIKE '%insulin%' OR 
     p.drug IN ('Insulin', 'Insulin Regular', 'Insulin NPH', 'Insulin Glargine', 'Insulin Detemir', 'Insulin Aspart', 'Insulin Lispro')) AS is_insulin,
    (LOWER(p.drug) LIKE '%metformin%') AS is_metformin,
    (LOWER(p.drug) LIKE '%dapagliflozin%' OR 
     LOWER(p.drug) LIKE '%empagliflozin%' OR 
     LOWER(p.drug) LIKE '%canagliflozin%') AS is_sglt2i,
    (LOWER(p.drug) LIKE '%liraglutide%' OR 
     LOWER(p.drug) LIKE '%semaglutide%' OR 
     LOWER(p.drug) LIKE '%exenatide%') AS is_glp1,
    (LOWER(p.drug) LIKE '%sitagliptin%' OR 
     LOWER(p.drug) LIKE '%saxagliptin%' OR 
     LOWER(p.drug) LIKE '%linagliptin%') AS is_dpp4,
    -- Cardiac classes
    (LOWER(p.drug) LIKE '%metoprolol%' OR 
     LOWER(p.drug) LIKE '%carvedilol%' OR 
     LOWER(p.drug) LIKE '%bisoprolol%' OR 
     LOWER(p.drug) LIKE '%atenolol%') AS is_beta_blocker,
    (LOWER(p.drug) LIKE '%lisinopril%' OR 
     LOWER(p.drug) LIKE '%enalapril%' OR 
     LOWER(p.drug) LIKE '%ramipril%') AS is_acei,
    (LOWER(p.drug) LIKE '%losartan%' OR 
     LOWER(p.drug) LIKE '%valsartan%' OR 
     LOWER(p.drug) LIKE '%irbesartan%') AS is_arb,
    (LOWER(p.drug) LIKE '%furosemide%' OR 
     LOWER(p.drug) LIKE '%bumetanide%' OR 
     LOWER(p.drug) LIKE '%hydrochlorothiazide%' OR 
     LOWER(p.drug) LIKE '%chlorthalidone%') AS is_diuretic,
    (LOWER(p.drug) LIKE '%spironolactone%' OR 
     LOWER(p.drug) LIKE '%eplerenone%') AS is_aldactone,
    -- Timing
    p.starttime,
    p.stoptime,
    c.admittime,
    c.dischtime,
    DATETIME_ADD(c.admittime, INTERVAL 48 HOUR) AS first_48h_end,
    DATETIME_SUB(c.dischtime, INTERVAL 12 HOUR) AS last_12h_start
  FROM cohort_with_dx c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON c.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
),
drug_window AS (
  SELECT
    hadm_id,
    -- First 48h: drug started within first 48h of admission
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_insulin ELSE FALSE END) AS insulin_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_metformin ELSE FALSE END) AS metformin_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_sglt2i ELSE FALSE END) AS sglt2i_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_glp1 ELSE FALSE END) AS glp1_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_dpp4 ELSE FALSE END) AS dpp4_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_beta_blocker ELSE FALSE END) AS beta_blocker_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_acei ELSE FALSE END) AS acei_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_arb ELSE FALSE END) AS arb_first_48h,
    MAX(CASE WHEN starttime >= admittime AND starttime <= first_48h_end THEN is_diuretic ELSE FALSE END) AS diuretic_first_48h,
    MAX(CASE WHEN;