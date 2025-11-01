WITH
-- Identify female patients aged 83-93 with T2DM and HF
patient_cohort AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 83 AND 93
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          -- T2DM ICD-10 codes
          (di.icd_version = 10 AND di.icd_code IN ('E11', 'E11.0', 'E11.1', 'E11.2', 'E11.3', 'E11.4', 'E11.5', 'E11.6', 'E11.7', 'E11.8', 'E11.9'))
          OR
          -- T2DM ICD-9 codes
          (di.icd_version = 9 AND di.icd_code IN ('250.00', '250.02', '250.10', '250.12', '250.20', '250.22', '250.30', '250.32', '250.40', '250.42', '250.50', '250.52', '250.60', '250.62', '250.70', '250.72', '250.80', '250.82', '250.90', '250.92'))
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.subject_id = p.subject_id
        AND di.hadm_id = a.hadm_id
        AND (
          -- HF ICD-10 codes
          (di.icd_version = 10 AND di.icd_code IN ('I50', 'I50.1', 'I50.2', 'I50.3', 'I50.4', 'I50.9'))
          OR
          -- HF ICD-9 codes
          (di.icd_version = 9 AND di.icd_code IN ('428.0', '428.1', '428.2', '428.3', '428.4', '428.9'))
        )
    )
),

-- Identify insulin prescriptions
insulin_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.admittime,
    p.dischtime,
    pr.starttime AS prescription_starttime,
    pr.drug,
    pr.route,
    ph.sliding_scale,
    CASE
      WHEN LOWER(pr.drug) LIKE '%glargine%' OR LOWER(pr.drug) LIKE '%detemir%' OR LOWER(pr.drug) LIKE '%degludec%' THEN 'basal'
      WHEN LOWER(pr.drug) LIKE '%aspart%' OR LOWER(pr.drug) LIKE '%lispro%' OR LOWER(pr.drug) LIKE '%glulisine%' THEN 'bolus'
      WHEN ph.sliding_scale = 'Yes' THEN 'sliding_scale'
      ELSE NULL
    END AS insulin_type
  FROM
    patient_cohort p
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` pr ON p.hadm_id = pr.hadm_id
  LEFT JOIN
    `physionet-data.mimiciv_3_1_hosp.pharmacy` ph ON pr.pharmacy_id = ph.pharmacy_id
  WHERE
    (LOWER(pr.drug) LIKE '%insulin%'
     OR LOWER(pr.drug) LIKE '%glargine%'
     OR LOWER(pr.drug) LIKE '%detemir%'
     OR LOWER(pr.drug) LIKE '%degludec%'
     OR LOWER(pr.drug) LIKE '%aspart%'
     OR LOWER(pr.drug) LIKE '%lispro%'
     OR LOWER(pr.drug) LIKE '%glulisine%'
     OR ph.sliding_scale = 'Yes')
),

-- First 48 hours insulin initiations
first_48h_initiations AS (
  SELECT
    subject_id,
    hadm_id,
    insulin_type,
    COUNT(DISTINCT hadm_id) AS count
  FROM
    insulin_prescriptions
  WHERE
    TIMESTAMP_DIFF(prescription_starttime, admittime, HOUR) BETWEEN 0 AND 48
  GROUP BY
    subject_id, hadm_id, insulin_type
),

-- Final 12 hours insulin initiations
final_12h_initiations AS (
  SELECT
    subject_id,
    hadm_id,
    insulin_type,
    COUNT(DISTINCT hadm_id) AS count
  FROM
    insulin_prescriptions
  WHERE
    TIMESTAMP_DIFF(dischtime, prescription_starttime, HOUR) BETWEEN 0 AND 12
  GROUP BY
    subject_id, hadm_id, insulin_type
),

-- Count of patients in each time window
patient_counts AS (
  SELECT
    COUNT(DISTINCT hadm_id) AS total_patients
  FROM
    patient_cohort
)

-- Final results
SELECT
  'First 48 hours' AS time_window,
  SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) AS basal_count,
  SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) AS bolus_count,
  SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) AS sliding_scale_count,
  SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) * 100.0 / (SELECT total_patients FROM patient_counts) AS basal_percentage,
  SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) * 100.0 / (SELECT total_patients FROM patient_counts) AS bolus_percentage,
  SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) * 100.0 / (SELECT total_patients FROM patient_counts) AS sliding_scale_percentage
FROM
  first_48h_initiations

UNION ALL

SELECT
  'Final 12 hours' AS time_window,
  SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) AS basal_count,
  SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) AS bolus_count,
  SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) AS sliding_scale_count,
  SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) * 100.0 / (SELECT total_patients FROM patient_counts) AS basal_percentage,
  SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) * 100.0 / (SELECT total_patients FROM patient_counts) AS bolus_percentage,
  SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) * 100.0 / (SELECT total_patients FROM patient_counts) AS sliding_scale_percentage
FROM
  final_12h_initiations

UNION ALL

SELECT
  'Net Change' AS time_window,
  SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) -
    (SELECT SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) FROM first_48h_initiations) AS basal_count,
  SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) -
    (SELECT SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) FROM first_48h_initiations) AS bolus_count,
  SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) -
    (SELECT SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) FROM first_48h_initiations) AS sliding_scale_count,
  (SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) -
    (SELECT SUM(CASE WHEN insulin_type = 'basal' THEN count ELSE 0 END) FROM first_48h_initiations)) * 100.0 /
    (SELECT total_patients FROM patient_counts) AS basal_percentage,
  (SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) -
    (SELECT SUM(CASE WHEN insulin_type = 'bolus' THEN count ELSE 0 END) FROM first_48h_initiations)) * 100.0 /
    (SELECT total_patients FROM patient_counts) AS bolus_percentage,
  (SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) -
    (SELECT SUM(CASE WHEN insulin_type = 'sliding_scale' THEN count ELSE 0 END) FROM first_48h_initiations)) * 100.0 /
    (SELECT total_patients FROM patient_counts) AS sliding_scale_percentage
FROM
  final_12h_initiations;