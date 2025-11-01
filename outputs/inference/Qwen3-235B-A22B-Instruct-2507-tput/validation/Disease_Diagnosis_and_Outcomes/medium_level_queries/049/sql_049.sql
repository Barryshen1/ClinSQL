with MI (STEMI/NSTEMI) and compute age at admission
WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    -- Compute age at this admission
    (EXTRACT(YEAR FROM a.admittime) + EXTRACT(DOY FROM a.admittime) / 365.25)
    - (p.anchor_year - p.anchor_age) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
),

-- Step 2: Filter to males aged 51–61 at admission
filtered_patients AS (
  SELECT *
  FROM patient_admissions
  WHERE gender = 'M'
    AND age_at_admit >= 51
    AND age_at_admit <= 61
),

-- Step 3: Get diagnoses and join with d_icd_diagnoses for code details
diagnoses_with_details AS (
  SELECT
    di.subject_id,
    di.hadm_id,
    di.icd_code,
    di.icd_version,
    di.seq_num,
    d_icd.long_title
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_icd
    ON di.icd_code = d_icd.icd_code AND di.icd_version = d_icd.icd_version
  WHERE di.icd_version = 10
),

-- Step 4: Identify MI type per admission (STEMI: I21.0-I21.3; NSTEMI: I21.4)
mi_diagnoses AS (
  SELECT
    hadm_id,
    seq_num,
    CASE
      WHEN icd_code IN ('I210', 'I211', 'I212', 'I213') THEN 'STEMI'
      WHEN icd_code = 'I214' THEN 'NSTEMI'
      ELSE NULL
    END AS mi_type
  FROM diagnoses_with_details
  WHERE (icd_code IN ('I210', 'I211', 'I212', 'I213') OR icd_code = 'I214')
),

-- Step 5: Assign primary MI type by lowest seq_num
primary_mi AS (
  SELECT
    hadm_id,
    mi_type
  FROM (
    SELECT
      hadm_id,
      mi_type,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY seq_num) AS rn
    FROM mi_diagnoses
  )
  WHERE rn = 1
),

-- Step 6: Define comorbidities for each admission
comorbidities AS (
  SELECT
    hadm_id,
    -- Diabetes: E10, E11, E13, E14
    MAX(CASE WHEN icd_code LIKE 'E10%' OR icd_code LIKE 'E11%' OR icd_code LIKE 'E13%' OR icd_code LIKE 'E14%' THEN 1 ELSE 0 END) AS has_diabetes,
    -- CKD: N18
    MAX(CASE WHEN icd_code LIKE 'N18%' THEN 1 ELSE 0 END) AS has_ckd,
    -- Hypertension: I10-I15
    MAX(CASE WHEN icd_code LIKE 'I10%' OR icd_code LIKE 'I11%' OR icd_code LIKE 'I12%' OR icd_code LIKE 'I13%' OR icd_code LIKE 'I15%' THEN 1 ELSE 0 END) AS has_hypertension,
    -- Heart failure: I50
    MAX(CASE WHEN icd_code LIKE 'I50%' THEN 1 ELSE 0 END) AS has_heart_failure,
    -- Atrial fibrillation: I48
    MAX(CASE WHEN icd_code LIKE 'I48%' THEN 1 ELSE 0 END) AS has_afib,
    -- COPD: J44
    MAX(CASE WHEN icd_code LIKE 'J44%' THEN 1 ELSE 0 END) AS has_copd,
    -- Liver disease: K70, K73, K74, K76.0, K76.2-K76.4, K76.8, K76.9, I86.4
    MAX(CASE WHEN icd_code LIKE 'K70%' OR icd_code LIKE 'K73%' OR icd_code LIKE 'K74%' 
              OR icd_code = 'K760' OR icd_code LIKE 'K762%' OR icd_code LIKE 'K763%' 
              OR icd_code LIKE 'K764%' OR icd_code LIKE 'K768%' OR icd_code LIKE 'K769%' 
              OR icd_code = 'I864' THEN 1 ELSE 0 END) AS has_liver,
    -- Stroke: I60-I69
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) IN ('I60', 'I61', 'I62', 'I63', 'I64', 'I65', 'I66', 'I67', 'I68', 'I69') THEN 1 ELSE 0 END) AS has_stroke,
    -- Peripheral vascular disease: I70, I71, I72, I73, I74, I77.1, I79.0, K55
    MAX(CASE WHEN SUBSTR(icd_code, 1, 3) IN ('I70', 'I71', 'I72', 'I73', 'I74')
              OR icd_code = 'I771' OR icd_code = 'I790' OR icd_code LIKE 'K55%' THEN 1 ELSE 0 END) AS has_pvd
  FROM diagnoses_with_details
  GROUP BY hadm_id
),

-- Step 7: Combine all data
cohort AS (
  SELECT
    fp.hadm_id,
    fp.hospital_expire_flag,
    pm.mi_type,
    -- Compute LOS in days (fractional)
    DATETIME_DIFF(fp.dischtime, fp.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    -- Comorbidity count
    (COALESCE(c.has_diabetes, 0) + COALESCE(c.has_ckd, 0) + COALESCE(c.has_hypertension, 0) +
     COALESCE(c.has_heart_failure, 0) + COALESCE(c.has_afib, 0) + COALESCE(c.has_copd, 0) +
     COALESCE(c.has_liver, 0) + COALESCE(c.has_stroke, 0) + COALESCE(c.has_pvd, 0)) AS comorbidity_count,
    c.has_ckd,
    c.has_diabetes
  FROM filtered_patients fp
  INNER JOIN primary_mi pm
    ON fp.hadm_id = pm.hadm_id
  LEFT JOIN comorbidities c
    ON fp.hadm_id = c.hadm_id
  WHERE pm.mi_type IS NOT NULL
),

-- Step 8: Categorize LOS and comorbidity count
categorized;