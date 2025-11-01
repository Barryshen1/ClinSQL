WITH patient_cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.anchor_age BETWEEN 48 AND 58
),
t2dm_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'E11%'
),
hf_diagnoses AS (
  SELECT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE d.icd_code LIKE 'I50%'
),
qualified_admissions AS (
  SELECT pc.hadm_id, pc.admittime, pc.dischtime
  FROM patient_cohort pc
  WHERE EXISTS (SELECT 1 FROM t2dm_diagnoses t WHERE t.hadm_id = pc.hadm_id)
    AND EXISTS (SELECT 1 FROM hf_diagnoses h WHERE h.hadm_id = pc.hadm_id)
),
gpl1_drugs AS (
  SELECT DISTINCT hadm_id,
    MIN(starttime) AS first_start
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) IN (
    'liraglutide', 'dulaglutide', 'semaglutide', 'exenatide', 'albiglutide', 'lixisenatide'
  )
    AND LOWER(route) NOT LIKE '%oral%' -- ensure injectable
    AND drug_type = 'MAIN' -- primary drug entry
  GROUP BY hadm_id
),
initiation_timing AS (
  SELECT
    qa.hadm_id,
    CASE 
      WHEN gd.first_start IS NOT NULL 
       AND DATETIME_DIFF(gd.first_start, qa.admittime, HOUR) <= 72 
      THEN 1 ELSE 0 END AS initiated_72h,
    CASE 
      WHEN gd.first_start IS NOT NULL 
       AND DATETIME_DIFF(qa.dischtime, gd.first_start, HOUR) <= 48 
      THEN 1 ELSE 0 END AS initiated_last_48h
  FROM qualified_admissions qa
  LEFT JOIN gpl1_drugs gd ON qa.hadm_id = gd.hadm_id
),
summary AS (
  SELECT
    COUNT(*) AS total_admissions,
    AVG(initiated_72h) AS pct_72h,
    AVG(initiated_last_48h) AS pct_last_48h
  FROM initiation_timing
)
SELECT
  ROUND(pct_72h * 100, 2) AS initiation_rate_first_72h_pct,
  ROUND(pct_last_48h * 100, 2) AS initiation_rate_last_48h_pct,
  ROUND((pct_72h - pct_last_48h) * 100, 2) AS absolute_difference_pp
FROM summary;