WITH
-- Define age range and gender
patient_demographics AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 39 AND 49
),

-- Get admissions with LOS >= 72 hours
qualifying_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_demographics p ON a.subject_id = p.subject_id
  WHERE
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- Identify patients with T2DM and heart failure
diabetes_heart_failure AS (
  SELECT
    qa.subject_id,
    qa.hadm_id,
    qa.admittime,
    qa.dischtime,
    qa.los_hours
  FROM
    qualifying_admissions qa
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
      WHERE
        di.subject_id = qa.subject_id
        AND di.hadm_id = qa.hadm_id
        AND (
          -- T2DM codes (ICD-9 and ICD-10)
          (di.icd_version = 9 AND di.icd_code LIKE '250.%')
          OR (di.icd_version = 10 AND di.icd_code LIKE 'E11.%')
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
      WHERE
        di.subject_id = qa.subject_id
        AND di.hadm_id = qa.hadm_id
        AND (
          -- Heart failure codes (ICD-9 and ICD-10)
          (di.icd_version = 9 AND di.icd_code IN ('428.0', '428.1', '428.20', '428.21', '428.22', '428.23', '428.30', '428.31', '428.32', '428.33', '428.40', '428.41', '428.42', '428.43', '428.9'))
          OR (di.icd_version = 10 AND di.icd_code LIKE 'I50.%')
          OR (di.icd_version = 10 AND di.icd_code IN ('I11.0', 'I13.0', 'I13.2'))
        )
    )
),

-- Identify insulin prescriptions in first 72 hours
first_72h_insulin AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%basal%' OR LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%degludec%' THEN 'basal'
      WHEN LOWER(p.drug) LIKE '%bolus%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%glulisine%' THEN 'bolus'
      WHEN LOWER(p.drug) LIKE '%sliding%' OR LOWER(p.drug) LIKE '%scale%' THEN 'sliding_scale'
      ELSE NULL
    END AS insulin_type
  FROM
    diabetes_heart_failure d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON d.hadm_id = p.hadm_id
  WHERE
    TIMESTAMP_DIFF(p.starttime, d.admittime, HOUR) BETWEEN 0 AND 72
    AND LOWER(p.drug) LIKE '%insulin%'
),

-- Identify insulin prescriptions in final 48 hours
final_48h_insulin AS (
  SELECT
    d.subject_id,
    d.hadm_id,
    CASE
      WHEN LOWER(p.drug) LIKE '%basal%' OR LOWER(p.drug) LIKE '%glargine%' OR LOWER(p.drug) LIKE '%detemir%' OR LOWER(p.drug) LIKE '%degludec%' THEN 'basal'
      WHEN LOWER(p.drug) LIKE '%bolus%' OR LOWER(p.drug) LIKE '%aspart%' OR LOWER(p.drug) LIKE '%lispro%' OR LOWER(p.drug) LIKE '%glulisine%' THEN 'bolus'
      WHEN LOWER(p.drug) LIKE '%sliding%' OR LOWER(p.drug) LIKE '%scale%' THEN 'sliding_scale'
      ELSE NULL
    END AS insulin_type
  FROM
    diabetes_heart_failure d
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON d.hadm_id = p.hadm_id
  WHERE
    TIMESTAMP_DIFF(d.dischtime, p.starttime, HOUR) BETWEEN 0 AND 48
    AND LOWER(p.drug) LIKE '%insulin%'
),

-- Aggregate insulin regimens for first 72 hours
first_72h_regimens AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS has_basal,
    MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS has_bolus,
    MAX(CASE WHEN insulin_type = 'sliding_scale' THEN 1 ELSE 0 END) AS has_sliding_scale
  FROM
    first_72h_insulin
  GROUP BY
    subject_id, hadm_id
),

-- Aggregate insulin regimens for final 48 hours
final_48h_regimens AS (
  SELECT
    subject_id,
    hadm_id,
    MAX(CASE WHEN insulin_type = 'basal' THEN 1 ELSE 0 END) AS has_basal,
    MAX(CASE WHEN insulin_type = 'bolus' THEN 1 ELSE 0 END) AS has_bolus,
    MAX(CASE WHEN insulin_type = 'sliding_scale' THEN 1 ELSE 0 END) AS has_sliding_scale
  FROM
    final_48h_insulin
  GROUP BY
    subject_id, hadm_id
),

-- Determine regimen types for first 72 hours
first_72h_regimen_types AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'basal_bolus'
      WHEN has_basal = 1 THEN 'basal'
      WHEN has_bolus = 1 THEN 'bolus'
      WHEN has_sliding_scale = 1 THEN 'sliding_scale'
      ELSE 'none'
    END AS regimen_type
  FROM
    first_72h_regimens
),

-- Determine regimen types for final 48 hours
final_48h_regimen_types AS (
  SELECT
    subject_id,
    hadm_id,
    CASE
      WHEN has_basal = 1 AND has_bolus = 1 THEN 'basal_bolus'
      WHEN has_basal = 1 THEN 'basal'
      WHEN has_bolus = 1 THEN 'bolus'
      WHEN has_sliding_scale = 1 THEN 'sliding_scale'
      ELSE 'none'
    END AS regimen_type
  FROM
    final_48h_regimens
),

-- Count patients by regimen type in each time window
first_72h_counts AS (
  SELECT
    regimen_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    first_72h_regimen_types
  GROUP BY
    regimen_type
),

final_48h_counts AS (
  SELECT
    regimen_type,
    COUNT(DISTINCT subject_id) AS patient_count
  FROM
    final_48h_regimen_types
  GROUP BY
    regimen_type
),

-- Calculate percentages for each time window
first_72h_percentages AS (
  SELECT
    regimen_type,
    patient_count,
    ROUND(patient_count * 100.0 / SUM(patient_count) OVER(), 2) AS percentage
  FROM
    first_72h_counts
),

final_48h_percentages AS (
  SELECT
    regimen_type,
    patient_count,
    ROUND(patient_count * 100.0 / SUM(patient_count) OVER(), 2) AS percentage
  FROM
    final_48h_counts
),

-- Combine results for final output
combined_results AS (
  SELECT
    'first_72h' AS time_window,
    regimen_type,
    percentage
  FROM
    first_72h_percentages

  UNION ALL

  SELECT
    'final_48h' AS time_window,
    regimen_type,
    percentage
  FROM
    final_48h_percentages
),

-- Calculate absolute percentage-point differences
differences AS (
  SELECT
    f.regimen_type,
    f.percentage AS first_72h_percentage,
    l.percentage AS final_48h_percentage,
    ROUND(l.percentage - f.percentage, 2) AS absolute_difference
  FROM
    first_72h_percentages f
  JOIN
    final_48h_percentages l
    ON f.regimen_type = l.regimen_type
)

-- Final output
SELECT
  regimen_type,
  first_72h_percentage,
  final_48h_percentage,
  absolute_difference
FROM
  differences
ORDER BY
  regimen_type;