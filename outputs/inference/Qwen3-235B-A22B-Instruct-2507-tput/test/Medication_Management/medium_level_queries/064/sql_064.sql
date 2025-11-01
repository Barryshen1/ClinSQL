WITH patient_cohort AS (
  SELECT DISTINCT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp`.patients p ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 71 AND 81
),
diabetes_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (icd_version = 10 AND (LOWER(long_title) LIKE '%type 2 diabetes%' 
         OR LOWER(long_title) LIKE '%diabetes mellitus type 2%'))
     OR (icd_version = 9 AND icd_code LIKE '250%')
),
hf_codes AS (
  SELECT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses
  WHERE (icd_version = 10 AND LOWER(long_title) LIKE '%acute heart failure%')
     OR (icd_version = 9 AND icd_code LIKE '428.2%')
),
cohort_with_comorbidities AS (
  SELECT pc.*
  FROM patient_cohort pc
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = pc.hadm_id
      AND di.icd_code IN (SELECT icd_code FROM diabetes_codes)
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    WHERE di.hadm_id = pc.hadm_id
      AND di.icd_code IN (SELECT icd_code FROM hf_codes)
  )
),
drug_mapping AS (
  SELECT 
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(drug) IN ('glipizide', 'glyburide', 'glimepiride', 'tolbutamide', 'acetohexamide', 'chlorpropamide', 'tolazamide') THEN 'sulfonylureas'
      WHEN LOWER(drug) IN ('sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin') THEN 'DPP-4'
      WHEN LOWER(drug) IN ('empagliflozin', 'dapagliflozin', 'canagliflozin') THEN 'SGLT2'
      WHEN LOWER(drug) IN ('pioglitazone', 'rosiglitazone') THEN 'thiazolidinediones'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions
  WHERE LOWER(drug) IN (
    'metformin', 'glipizide', 'glyburide', 'glimepiride', 'tolbutamide', 'acetohexamide', 'chlorpropamide', 'tolazamide',
    'sitagliptin', 'saxagliptin', 'linagliptin', 'alogliptin',
    'empagliflozin', 'dapagliflozin', 'canagliflozin',
    'pioglitazone', 'rosiglitazone'
  )
),
prescriptions_with_class AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    dm.drug_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  JOIN drug_mapping dm ON LOWER(p.drug) = LOWER(dm.drug)
  WHERE dm.drug_class IS NOT NULL
),
first_prescriptions AS (
  SELECT 
    hadm_id,
    drug_class,
    starttime,
    ROW_NUMBER() OVER (PARTITION BY hadm_id, drug_class ORDER BY starttime) AS rn
  FROM prescriptions_with_class
),
initiation_timing AS (
  SELECT 
    c.hadm_id,
    fp.drug_class,
    CASE 
      WHEN fp.starttime <= c.admittime + INTERVAL '72' HOUR 
        AND fp.starttime >= c.admittime 
        THEN 'first_72h'
      WHEN fp.starttime >= c.dischtime - INTERVAL '48' HOUR 
        AND fp.starttime <= c.dischtime 
        THEN 'last_48h'
      ELSE NULL
    END AS time_window
  FROM cohort_with_comorbidities c
  JOIN first_prescriptions fp ON c.hadm_id = fp.hadm_id
  WHERE fp.rn = 1
    AND fp.starttime IS NOT NULL
),
cohort_counts AS (
  SELECT COUNT(*) AS total_patients
  FROM cohort_with_comorbidities
)
SELECT
  drug_class,
  time_window,
  COUNT(*) AS initiation_count,
  total_patients,
  ROUND(COUNT(*) * 100.0 / total_patients, 2) AS initiation_rate_pct
FROM initiation_timing
CROSS JOIN cohort_counts
WHERE time_window IS NOT NULL
GROUP BY drug_class, time_window, total_patients
ORDER BY drug_class, time_window;