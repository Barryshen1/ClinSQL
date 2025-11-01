WITH patient_admissions AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.dischtime - a.admittime AS los_interval
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age >= 50 AND p.anchor_age <= 60
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),
diabetes_hf AS (
  SELECT 
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime
  FROM patient_admissions pa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diab
    ON pa.hadm_id = diab.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_dia
    ON diab.icd_code = d_dia.icd_code AND diab.icd_version = d_dia.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd hf
    ON pa.hadm_id = hf.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d_hf
    ON hf.icd_code = d_hf.icd_code AND hf.icd_version = d_hf.icd_version
  WHERE 
    -- Type 2 diabetes: ICD-10 E11
    d_dia.icd_code LIKE 'E11%' AND d_dia.icd_version = 10
    AND
    -- Heart failure: ICD-10 I50
    d_hf.icd_code LIKE 'I50%' AND d_hf.icd_version = 10
),
glp1_drugs AS (
  SELECT 
    hadm_id,
    starttime,
    stoptime,
    drug
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) IN (
    'liraglutide', 'semaglutide', 'dulaglutide', 
    'exenatide', 'lixisenatide'
  )
    OR LOWER(drug) LIKE '%liraglutide%'
    OR LOWER(drug) LIKE '%semaglutide%'
    OR LOWER(drug) LIKE '%dulaglutide%'
    OR LOWER(drug) LIKE '%exenatide%'
    OR LOWER(drug) LIKE '%lixisenatide%'
),
exposure AS (
  SELECT 
    dh.hadm_id,
    -- First 12h initiation: started within 12h of admission
    MAX(CASE 
      WHEN g.starttime IS NOT NULL 
       AND g.starttime >= dh.admittime 
       AND g.starttime <= DATETIME_ADD(dh.admittime, INTERVAL 12 HOUR)
      THEN 1 ELSE 0 END) AS initiated_12h,
    -- Final 72h prevalence: active in last 72h of admission
    MAX(CASE 
      WHEN g.starttime IS NOT NULL 
       AND g.starttime <= dh.dischtime
       AND (g.stoptime IS NULL OR g.stoptime >= DATETIME_SUB(dh.dischtime, INTERVAL 72 HOUR))
       AND g.starttime < dh.dischtime -- avoid start at discharge
      THEN 1 ELSE 0 END) AS prevalent_72h
  FROM diabetes_hf dh
  LEFT JOIN glp1_drugs g
    ON dh.hadm_id = g.hadm_id
  GROUP BY dh.hadm_id
),
summary_stats AS (
  SELECT 
    AVG(initiated_12h) AS initiation_rate_12h,
    AVG(prevalent_72h) AS prevalence_rate_72h
  FROM exposure
)
SELECT 
  ROUND(initiation_rate_12h * 100, 2) AS first_12h_initiation_pct,
  ROUND(prevalence_rate_72h * 100, 2) AS final_72h_prevalence_pct,
  ROUND((prevalence_rate_72h - initiation_rate_12h) * 100, 2) AS net_percentage_point_change
FROM summary_stats;