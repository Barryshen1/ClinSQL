WITH patient_admissions AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.dischtime - a.admittime AS los,
    -- Calculate age at admission
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
    AND (a.dischtime - a.admittime) >= INTERVAL '48' HOUR
),
-- Get admissions with T2DM and Heart Failure
t2dm_hf_admissions AS (
  SELECT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime,
    pa.age_at_admit
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di1
    ON pa.hadm_id = di1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di2
    ON pa.hadm_id = di2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE d1.icd_code LIKE 'E11%' AND d1.icd_version = 10  -- T2DM
    AND d2.icd_code LIKE 'I50%' AND d2.icd_version = 10  -- Heart Failure
    AND pa.age_at_admit BETWEEN 59 AND 69
),
-- Identify GLP-1 agonists (injectable) in prescriptions
glp1_drugs AS (
  SELECT DISTINCT
    LOWER(drug) AS drug_name
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) IN ('liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'lixisenatide')
    OR EXISTS (
      SELECT 1
      FROM UNNEST(SPLIT(gsn, ';')) AS gs
      WHERE TRIM(LOWER(gs)) IN ('liraglutide', 'semaglutide', 'exenatide', 'dulaglutide', 'lixisenatide')
    )
),
-- Flag GLP-1 use in first 48h and final 12h
glp1_usage AS (
  SELECT
    tha.hadm_id,
    -- First 48h: started within 48h of admission
    MAX(CASE
      WHEN p.starttime >= tha.admittime
       AND p.starttime <= tha.admittime + INTERVAL '48' HOUR
       THEN 1 ELSE 0 END) AS used_glp1_first_48h,
    -- Final 12h: active in last 12h before discharge
    MAX(CASE
      WHEN (p.starttime <= tha.dischtime AND p.stoptime >= tha.dischtime - INTERVAL '12' HOUR)
        OR (p.starttime <= tha.dischtime AND p.stoptime IS NULL)
        THEN 1 ELSE 0 END) AS used_glp1_final_12h
  FROM t2dm_hf_admissions tha
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp`.prescriptions p
    ON tha.hadm_id = p.hadm_id
  INNER JOIN glp1_drugs g
    ON LOWER(p.drug) = g.drug_name
  WHERE (LOWER(p.route) LIKE '%subcut%' OR LOWER(p.route) LIKE '%inj%')
    AND p.drug IS NOT NULL
  GROUP BY tha.hadm_id
),
-- Aggregate prevalence
prevalence AS (
  SELECT
    AVG(used_glp1_first_48h) AS prev_first_48h,
    AVG(used_glp1_final_12h) AS prev_final_12h,
    COUNT(*) AS n
  FROM glp1_usage
)
-- Final output: prevalence and absolute difference
SELECT
  ROUND(prev_first_48h, 4) AS prevalence_first_48h,
  ROUND(prev_final_12h, 4) AS prevalence_final_12h,
  ROUND(ABS(prev_final_12h - prev_first_48h), 4) AS absolute_difference,
  n AS total_patients
FROM prevalence;