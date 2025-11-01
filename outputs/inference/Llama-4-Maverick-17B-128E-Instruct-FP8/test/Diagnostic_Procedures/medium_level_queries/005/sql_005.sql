WITH 
-- Filter patients
patients_filtered AS (
  SELECT subject_id, anchor_age, anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F' AND anchor_age BETWEEN 49 AND 59
),

-- Identify ischemic stroke admissions
ischemic_stroke_admissions AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id, 
         CASE 
           WHEN diag.icd_version = 9 AND (diag.icd_code LIKE '433%' OR diag.icd_code LIKE '434%' OR diag.icd_code LIKE '436%') THEN 1
           WHEN diag.icd_version = 10 AND diag.icd_code LIKE 'I63%' THEN 1
           ELSE 0
         END AS ischemic_stroke
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON ad.hadm_id = diag.hadm_id
  WHERE ad.subject_id IN (SELECT subject_id FROM patients_filtered)
),

-- Calculate length of stay and count procedures
admission_details AS (
  SELECT ad.hadm_id, 
         ad.admittime, 
         ad.dischtime, 
         DATETIME_DIFF(ad.dischtime, ad.admittime, DAY) AS los,
         COUNT(proc.icd_code) AS num_procedures,
         MIN(diag.seq_num) AS min_diag_seq_num
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` ad
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` proc ON ad.hadm_id = proc.hadm_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag ON ad.hadm_id = diag.hadm_id
  WHERE ad.hadm_id IN (SELECT hadm_id FROM ischemic_stroke_admissions WHERE ischemic_stroke = 1)
  GROUP BY ad.hadm_id, ad.admittime, ad.dischtime
),

-- Categorize LOS and diagnosis type
final_data AS (
  SELECT 
    CASE 
      WHEN los BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN los BETWEEN 5 AND 8 THEN '5-8 days'
      ELSE 'other'
    END AS los_category,
    CASE 
      WHEN min_diag_seq_num = 1 THEN 'primary'
      ELSE 'secondary'
    END AS diagnosis_type,
    num_procedures
  FROM admission_details
  WHERE los BETWEEN 1 AND 8
)

-- Calculate mean, min, and max procedures
SELECT 
  los_category,
  diagnosis_type,
  AVG(num_procedures) AS mean_procedures,
  MIN(num_procedures) AS min_procedures,
  MAX(num_procedures) AS max_procedures
FROM final_data
GROUP BY los_category, diagnosis_type
ORDER BY los_category, diagnosis_type;