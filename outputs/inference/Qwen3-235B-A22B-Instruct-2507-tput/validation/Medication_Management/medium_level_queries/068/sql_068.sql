WITH patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age BETWEEN 83 AND 93
),
t2dm_diagnosis AS (
  SELECT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%diabetes mellitus type 2%'
     OR LOWER(d.long_title) LIKE '%type 2 diabetes%'
     OR (d.icd_code LIKE 'E11%' AND di.icd_version = 10)
),
hf_diagnosis AS (
  SELECT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE LOWER(d.long_title) LIKE '%heart failure%'
     OR LOWER(d.long_title) LIKE '%congestive heart failure%'
     OR LOWER(d.long_title) LIKE '%cardiomyopathy%'
     OR (d.icd_code IN ('I50', 'I50.9') AND di.icd_version = 10)
),
qualified_patients AS (
  SELECT pc.subject_id
  FROM patient_cohort pc
  INNER JOIN t2dm_diagnosis t2 ON pc.subject_id = t2.subject_id
  INNER JOIN hf_diagnosis hf ON pc.subject_id = hf.subject_id
),
insulin_prescriptions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.starttime,
    p.drug,
    -- Classify insulin type
    CASE
      WHEN LOWER(p.drug) LIKE '%basal%' OR LOWER(p.drug) LIKE '%long-acting%' THEN 'basal'
      WHEN LOWER(p.drug) LIKE '%bolus%' OR LOWER(p.drug) LIKE '%short-acting%' OR LOWER(p.drug) LIKE '%rapid-acting%' THEN 'bolus'
      WHEN (LOWER(p.drug) LIKE '%basal%' OR LOWER(p.drug) LIKE '%long-acting%') 
           AND (LOWER(p.drug) LIKE '%bolus%' OR LOWER(p.drug) LIKE '%short-acting%') THEN 'basal-bolus'
      WHEN LOWER(p.drug) LIKE '%sliding scale%' THEN 'sliding-scale'
      ELSE 'other'
    END AS insulin_type
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a ON p.hadm_id = a.hadm_id
  INNER JOIN qualified_patients qp ON a.subject_id = qp.subject_id
  WHERE LOWER(p.drug) LIKE '%insulin%'
    AND p.starttime IS NOT NULL
),
insulin_timing AS (
  SELECT 
    ip.subject_id,
    ip.hadm_id,
    ip.insulin_type,
    CASE 
      WHEN ip.starttime <= TIMESTAMP_ADD(ip.admittime, INTERVAL 48 HOUR) THEN 'first_48h'
      ELSE NULL 
    END AS in_first_48h,
    CASE 
      WHEN ip.starttime >= TIMESTAMP_SUB(ip.dischtime, INTERVAL 12 HOUR) THEN 'final_12h'
      ELSE NULL 
    END AS in_final_12h
  FROM insulin_prescriptions ip
),
aggregated AS (
  SELECT
    insulin_type,
    COUNT(DISTINCT CASE WHEN in_first_48h = 'first_48h' THEN subject_id END) AS first_48h_count,
    COUNT(DISTINCT CASE WHEN in_final_12h = 'final_12h' THEN subject_id END) AS final_12h_count,
    (SELECT COUNT(*) FROM qualified_patients) AS total_patients
  FROM insulin_timing
  WHERE insulin_type IN ('basal', 'bolus', 'basal-bolus', 'sliding-scale')
  GROUP BY insulin_type
)
SELECT
  insulin_type,
  ROUND(100.0 * first_48h_count / total_patients, 2) AS pct_first_48h,
  ROUND(100.0 * final_12h_count / total_patients, 2) AS pct_final_12h,
  ROUND(100.0 * (final_12h_count - first_48h_count) / total_patients, 2) AS net_change_pct
FROM aggregated
ORDER BY insulin_type;