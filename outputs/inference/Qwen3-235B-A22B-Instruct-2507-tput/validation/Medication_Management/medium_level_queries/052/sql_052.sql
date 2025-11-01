WITH type2_diabetes_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%type 2 diabetes%'
    AND icd_version = 10
),
heart_failure_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE LOWER(long_title) LIKE '%heart failure%'
    AND icd_version = 10
),
eligible_admissions AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd diab ON a.hadm_id = diab.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd hf ON a.hadm_id = hf.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 45 AND 55
    AND diab.icd_code IN (SELECT icd_code FROM type2_diabetes_codes)
    AND hf.icd_code IN (SELECT icd_code FROM heart_failure_codes)
    AND DATETIME_DIFF(a.dischtime, a.admittime, HOUR) >= 48
),
diabetes_medications AS (
  SELECT 
    rx.hadm_id,
    rx.drug,
    rx.route,
    rx.starttime,
    rx.stoptime,
    CASE 
      WHEN LOWER(rx.drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(rx.route) LIKE '%oral%' 
        AND LOWER(rx.drug) IN (
          'metformin', 'glipizide', 'glyburide', 'glimepiride', 
          'sitagliptin', 'linagliptin', 'empagliflozin', 'dapagliflozin', 
          'canagliflozin', 'pioglitazone', 'rosiglitazone', 'acarbose', 
          'miglitol', 'repaglinide', 'nateglinide'
        ) THEN 'Oral'
      ELSE NULL
    END AS med_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions rx
  WHERE rx.hadm_id IN (SELECT hadm_id FROM eligible_admissions)
    AND rx.starttime IS NOT NULL
),
cohort_stats AS (
  SELECT 
    COUNT(DISTINCT hadm_id) AS total_patients
  FROM eligible_admissions
),
first_48h_meds AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN med_class = 'Insulin' THEN hadm_id END) AS insulin_patients,
    COUNT(DISTINCT CASE WHEN med_class = 'Oral' THEN hadm_id END) AS oral_patients
  FROM diabetes_medications dm
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a USING (hadm_id)
  WHERE 
    -- Overlap with first 48 hours: [admittime, admittime + 48h]
    dm.starttime < DATETIME_ADD(a.admittime, INTERVAL 48 HOUR)
    AND (dm.stoptime IS NULL OR dm.stoptime > a.admittime)
),
final_24h_meds AS (
  SELECT 
    COUNT(DISTINCT CASE WHEN med_class = 'Insulin' THEN hadm_id END) AS insulin_patients,
    COUNT(DISTINCT CASE WHEN med_class = 'Oral' THEN hadm_id END) AS oral_patients
  FROM diabetes_medications dm
  JOIN `physionet-data.mimiciv_3_1_hosp`.admissions a USING (hadm_id)
  WHERE 
    -- Overlap with final 24 hours: [dischtime - 24h, dischtime]
    dm.starttime < a.dischtime
    AND (dm.stoptime IS NULL OR dm.stoptime > DATETIME_SUB(a.dischtime, INTERVAL 24 HOUR))
)
SELECT 
  'First 48h' AS time_window,
  ROUND(100.0 * f.insulin_patients / cs.total_patients, 2) AS insulin_pct,
  ROUND(100.0 * f.oral_patients / cs.total_patients, 2) AS oral_pct
FROM first_48h_meds f
CROSS JOIN cohort_stats cs

UNION ALL

SELECT 
  'Final 24h' AS time_window,
  ROUND(100.0 * l.insulin_patients / cs.total_patients, 2) AS insulin_pct,
  ROUND(100.0 * l.oral_patients / cs.total_patients, 2) AS oral_pct
FROM final_24h_meds l
CROSS JOIN cohort_stats cs;