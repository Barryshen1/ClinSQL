WITH
-- Define our patient cohort: males aged 71-81 with diabetes and acute heart failure
patient_cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag1 ON d1.icd_code = diag1.icd_code
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag2 ON d2.icd_code = diag2.icd_code
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 71 AND 81
    AND (
      -- Diabetes ICD codes (E11-E14)
      (diag1.icd_code BETWEEN 'E11' AND 'E14' AND diag1.icd_version = 10)
      OR
      -- Acute heart failure ICD codes
      (diag2.icd_code IN ('I50.1', 'I50.21', 'I50.23', 'I50.31', 'I50.33', 'I50.41', 'I50.43', 'I50.9') AND diag2.icd_version = 10)
    )
),

-- Identify medication orders in first 72 hours
first_72h_meds AS (
  SELECT
    subject_id,
    hadm_id,
    medication_class
  FROM (
    SELECT
      pc.subject_id,
      pc.hadm_id,
      CASE
        WHEN LOWER(pres.drug) LIKE '%metformin%' THEN 'Metformin'
        WHEN LOWER(pres.drug) LIKE '%glimepiride%' OR LOWER(pres.drug) LIKE '%glyburide%' OR LOWER(pres.drug) LIKE '%glipizide%' THEN 'Sulfonylureas'
        WHEN LOWER(pres.drug) LIKE '%sitagliptin%' OR LOWER(pres.drug) LIKE '%saxagliptin%' OR LOWER(pres.drug) LIKE '%linagliptin%' THEN 'DPP-4'
        WHEN LOWER(pres.drug) LIKE '%canagliflozin%' OR LOWER(pres.drug) LIKE '%dapagliflozin%' OR LOWER(pres.drug) LIKE '%empagliflozin%' THEN 'SGLT2'
        WHEN LOWER(pres.drug) LIKE '%pioglitazone%' OR LOWER(pres.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
        ELSE NULL
      END AS medication_class
    FROM patient_cohort pc
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres ON pc.hadm_id = pres.hadm_id
    WHERE pres.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 72 HOUR)
  )
  WHERE medication_class IS NOT NULL
),

-- Identify medication orders in last 48 hours
last_48h_meds AS (
  SELECT
    subject_id,
    hadm_id,
    medication_class
  FROM (
    SELECT
      pc.subject_id,
      pc.hadm_id,
      CASE
        WHEN LOWER(pres.drug) LIKE '%metformin%' THEN 'Metformin'
        WHEN LOWER(pres.drug) LIKE '%glimepiride%' OR LOWER(pres.drug) LIKE '%glyburide%' OR LOWER(pres.drug) LIKE '%glipizide%' THEN 'Sulfonylureas'
        WHEN LOWER(pres.drug) LIKE '%sitagliptin%' OR LOWER(pres.drug) LIKE '%saxagliptin%' OR LOWER(pres.drug) LIKE '%linagliptin%' THEN 'DPP-4'
        WHEN LOWER(pres.drug) LIKE '%canagliflozin%' OR LOWER(pres.drug) LIKE '%dapagliflozin%' OR LOWER(pres.drug) LIKE '%empagliflozin%' THEN 'SGLT2'
        WHEN LOWER(pres.drug) LIKE '%pioglitazone%' OR LOWER(pres.drug) LIKE '%rosiglitazone%' THEN 'Thiazolidinediones'
        ELSE NULL
      END AS medication_class
    FROM patient_cohort pc
    JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres ON pc.hadm_id = pres.hadm_id
    WHERE pres.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 48 HOUR) AND pc.dischtime
  )
  WHERE medication_class IS NOT NULL
),

-- Count patients in each medication class for each time window
med_counts AS (
  SELECT
    'First 72 hours' AS time_window,
    medication_class,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM first_72h_meds
  GROUP BY medication_class

  UNION ALL

  SELECT
    'Last 48 hours' AS time_window,
    medication_class,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM last_48h_meds
  GROUP BY medication_class
),

-- Total number of patients in our cohort
total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total_count
  FROM patient_cohort
)

-- Calculate initiation rates
SELECT
  mc.time_window,
  mc.medication_class,
  mc.patient_count,
  tp.total_count,
  ROUND((mc.patient_count / tp.total_count) * 100, 2) AS initiation_rate_percentage
FROM med_counts mc
CROSS JOIN total_patients tp
ORDER BY mc.time_window, mc.medication_class;