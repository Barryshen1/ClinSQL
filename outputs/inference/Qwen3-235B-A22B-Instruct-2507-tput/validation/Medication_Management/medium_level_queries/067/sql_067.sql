WITH patient_cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    -- Calculate age at admission
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 64 AND 74
    -- Must have diabetes diagnosis (ICD-10 E11*)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND d.icd_code LIKE 'E11%'
    )
    -- Must have acute heart failure (I50.2x or I50.3x)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
      JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d 
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.hadm_id = a.hadm_id
        AND d.icd_version = 10
        AND (d.icd_code LIKE 'I50.2%' OR d.icd_code LIKE 'I50.3%')
    )
),
drug_class_initiation AS (
  SELECT 
    pc.subject_id,
    pc.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(p.drug) IN ('glipizide', 'glyburide', 'gliburide', 'glimepiride') 
        OR LOWER(p.drug) LIKE '%sulfonylurea%' THEN 'sulfonylureas'
      WHEN LOWER(p.drug) IN ('sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin') 
        OR LOWER(p.drug) LIKE '%dpp-4%' THEN 'dpp-4'
      WHEN LOWER(p.drug) IN ('empagliflozin', 'canagliflozin', 'dapagliflozin', 'ertugliflozin') 
        OR LOWER(p.drug) LIKE '%sglt2%' THEN 'sglt2'
      WHEN LOWER(p.drug) IN ('liraglutide', 'semaglutide', 'dulaglutide', 'exenatide') 
        OR LOWER(p.drug) LIKE '%glp-1%' THEN 'glp-1'
      WHEN LOWER(p.drug) IN ('pioglitazone', 'rosiglitazone') 
        OR LOWER(p.drug) LIKE '%tzd%' THEN 'tzds'
      ELSE NULL
    END AS drug_class,
    p.starttime
  FROM patient_cohort pc
  JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p 
    ON pc.hadm_id = p.hadm_id
  WHERE p.starttime IS NOT NULL
    AND p.starttime >= pc.admittime
    AND p.starttime <= COALESCE(pc.dischtime, CURRENT_DATETIME())
),
first_exposure AS (
  SELECT 
    subject_id,
    drug_class,
    MIN(starttime) AS first_start
  FROM drug_class_initiation
  WHERE drug_class IS NOT NULL
  GROUP BY subject_id, drug_class
),
exposure_windows AS (
  SELECT 
    fe.subject_id,
    fe.drug_class,
    fe.first_start,
    pc.admittime,
    pc.dischtime,
    -- Flag if initiated in first 12h
    CASE 
      WHEN fe.first_start <= pc.admittime + INTERVAL '12' HOUR 
      THEN 1 ELSE 0 
    END AS initiated_first_12h,
    -- Flag if initiated in final 48h
    CASE 
      WHEN fe.first_start >= pc.dischtime - INTERVAL '48' HOUR 
      AND fe.first_start <= pc.dischtime
      THEN 1 ELSE 0 
    END AS initiated_final_48h
  FROM first_exposure fe
  JOIN patient_cohort pc ON fe.subject_id = pc.subject_id
),
summary AS (
  SELECT
    drug_class,
    AVG(initiated_first_12h) * 100 AS pct_initiated_first_12h,
    AVG(initiated_final_48h) * 100 AS pct_initiated_final_48h
  FROM exposure_windows
  GROUP BY drug_class
)
SELECT
  drug_class,
  ROUND(pct_initiated_first_12h, 2) AS pct_initiated_first_12h,
  ROUND(pct_initiated_final_48h, 2) AS pct_initiated_final_48h
FROM summary
ORDER BY drug_class;