WITH eligible_patients AS (
  SELECT 
    p.subject_id,  -- Fixed: qualified with table alias to resolve ambiguity
    anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND anchor_age + (EXTRACT(YEAR FROM admittime) - anchor_year) BETWEEN 75 AND 85
),

sufficient_duration AS (
  SELECT 
    hadm_id,
    admittime,
    dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions
  WHERE 
    TIMESTAMP_DIFF(dischtime, admittime, HOUR) >= 36
),

diabetes_diagnoses AS (
  SELECT DISTINCT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE 
    (icd_version = 9 AND icd_code LIKE '250%')
    OR (icd_version = 10 AND (
      icd_code LIKE 'E08%' OR 
      icd_code LIKE 'E09%' OR 
      icd_code LIKE 'E10%' OR 
      icd_code LIKE 'E11%' OR 
      icd_code LIKE 'E13%' OR 
      icd_code LIKE 'E14%'
    ))
),

acute_heart_failure_diagnoses AS (
  SELECT DISTINCT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd
  WHERE 
    icd_version = 10 AND 
    icd_code IN ('I5021', 'I5022', 'I5023', 'I5031', 'I5032', 'I5033', 'I5041', 'I50811')
),

base_population AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN eligible_patients ep
    ON a.subject_id = ep.subject_id
  INNER JOIN sufficient_duration sd
    ON a.hadm_id = sd.hadm_id
  INNER JOIN diabetes_diagnoses dd
    ON a.hadm_id = dd.hadm_id
  INNER JOIN acute_heart_failure_diagnoses ahf
    ON a.hadm_id = ahf.hadm_id
),

glp1_prescriptions AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    a.admittime,
    a.dischtime,
    ROW_NUMBER() OVER (PARTITION BY p.hadm_id ORDER BY p.starttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN base_population a
    ON p.hadm_id = a.hadm_id
  WHERE 
    (LOWER(p.drug) LIKE '%liraglutide%' OR
     LOWER(p.drug) LIKE '%semaglutide%' OR
     LOWER(p.drug) LIKE '%dulaglutide%' OR
     LOWER(p.drug) LIKE '%exenatide%') AND
    (LOWER(p.route) LIKE '%subcut%' OR 
     LOWER(p.route) = 'sc' OR
     LOWER(p.route) LIKE '%sub q%')
),

first_glp1_prescription AS (
  SELECT 
    hadm_id,
    CASE WHEN starttime < TIMESTAMP_ADD(admittime, INTERVAL 24 HOUR) 
         THEN 1 ELSE 0 END AS first_24h_flag,
    CASE WHEN starttime >= TIMESTAMP_SUB(dischtime, INTERVAL 12 HOUR) 
         THEN 1 ELSE 0 END AS final_12h_flag
  FROM glp1_prescriptions
  WHERE rn = 1
),

counts AS (
  SELECT 
    COUNT(*) AS total_patients,
    SUM(COALESCE(first_24h_flag, 0)) AS first_24h_count,
    SUM(COALESCE(final_12h_flag, 0)) AS final_12h_count
  FROM base_population bp
  LEFT JOIN first_glp1_prescription fgp
    ON bp.hadm_id = fgp.hadm_id
)

SELECT 
  ROUND((first_24h_count * 100.0 / total_patients), 2) AS percent_first_24h,
  ROUND((final_12h_count * 100.0 / total_patients), 2) AS percent_final_12h
FROM counts;