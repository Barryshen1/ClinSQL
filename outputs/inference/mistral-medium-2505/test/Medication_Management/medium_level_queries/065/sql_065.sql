WITH
-- Define age range and relevant diagnoses
patient_cohort AS (
  SELECT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN
    `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE
    -- Age 77-87 (using anchor_age as it's age at first admission)
    p.anchor_age BETWEEN 77 AND 87
    -- Male patients
    AND p.gender = 'M'
    -- Has diabetes (ICD-10 codes E11-E14 or ICD-9 250.x)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.subject_id = p.subject_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E12%' OR di.icd_code LIKE 'E13%' OR di.icd_code LIKE 'E14%')
          OR (di.icd_version = 9 AND di.icd_code LIKE '250%')
        )
    )
    -- Has heart failure (ICD-10 I50.x or ICD-9 428.x)
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
      WHERE di.subject_id = p.subject_id
        AND (
          (di.icd_version = 10 AND di.icd_code LIKE 'I50%')
          OR (di.icd_version = 9 AND di.icd_code LIKE '428%')
        )
    )
),

-- Identify insulin and oral diabetes medications
diabetes_meds AS (
  SELECT
    subject_id,
    hadm_id,
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' OR
           LOWER(drug) LIKE '%glipizide%' OR
           LOWER(drug) LIKE '%glyburide%' OR
           LOWER(drug) LIKE '%glimepiride%' OR
           LOWER(drug) LIKE '%pioglitazone%' OR
           LOWER(drug) LIKE '%rosiglitazone%' OR
           LOWER(drug) LIKE '%sitagliptin%' OR
           LOWER(drug) LIKE '%saxagliptin%' OR
           LOWER(drug) LIKE '%linagliptin%' OR
           LOWER(drug) LIKE '%alogliptin%' OR
           LOWER(drug) LIKE '%canagliflozin%' OR
           LOWER(drug) LIKE '%dapagliflozin%' OR
           LOWER(drug) LIKE '%empagliflozin%' OR
           LOWER(drug) LIKE '%ertugliflozin%' OR
           LOWER(drug) LIKE '%acarbose%' OR
           LOWER(drug) LIKE '%miglitol%' OR
           LOWER(drug) LIKE '%repaglinide%' OR
           LOWER(drug) LIKE '%nateglinide%'
      THEN 'Oral Agent'
      ELSE 'Other'
    END AS medication_type
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE
    LOWER(drug) LIKE '%insulin%' OR
    LOWER(drug) LIKE '%metformin%' OR
    LOWER(drug) LIKE '%glipizide%' OR
    LOWER(drug) LIKE '%glyburide%' OR
    LOWER(drug) LIKE '%glimepiride%' OR
    LOWER(drug) LIKE '%pioglitazone%' OR
    LOWER(drug) LIKE '%rosiglitazone%' OR
    LOWER(drug) LIKE '%sitagliptin%' OR
    LOWER(drug) LIKE '%saxagliptin%' OR
    LOWER(drug) LIKE '%linagliptin%' OR
    LOWER(drug) LIKE '%alogliptin%' OR
    LOWER(drug) LIKE '%canagliflozin%' OR
    LOWER(drug) LIKE '%dapagliflozin%' OR
    LOWER(drug) LIKE '%empagliflozin%' OR
    LOWER(drug) LIKE '%ertugliflozin%' OR
    LOWER(drug) LIKE '%acarbose%' OR
    LOWER(drug) LIKE '%miglitol%' OR
    LOWER(drug) LIKE '%repaglinide%' OR
    LOWER(drug) LIKE '%nateglinide%'
),

-- Get medication starts in first 48 hours
early_meds AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.drug) AS unique_meds
  FROM
    patient_cohort pc
  JOIN
    diabetes_meds dm ON pc.subject_id = dm.subject_id AND pc.hadm_id = dm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON dm.subject_id = p.subject_id AND dm.hadm_id = p.hadm_id AND dm.drug = p.drug
  WHERE
    TIMESTAMP_DIFF(p.starttime, pc.admittime, HOUR) BETWEEN 0 AND 48
  GROUP BY
    pc.subject_id, pc.hadm_id, dm.medication_type
),

-- Get medication starts in final 72 hours
late_meds AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    dm.medication_type,
    COUNT(DISTINCT dm.drug) AS unique_meds
  FROM
    patient_cohort pc
  JOIN
    diabetes_meds dm ON pc.subject_id = dm.subject_id AND pc.hadm_id = dm.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p ON dm.subject_id = p.subject_id AND dm.hadm_id = p.hadm_id AND dm.drug = p.drug
  WHERE
    TIMESTAMP_DIFF(pc.dischtime, p.starttime, HOUR) BETWEEN 0 AND 72
  GROUP BY
    pc.subject_id, pc.hadm_id, dm.medication_type
),

-- Count patients with each medication type in each period
early_counts AS (
  SELECT
    medication_type,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count
  FROM
    early_meds
  WHERE
    medication_type IN ('Insulin', 'Oral Agent')
  GROUP BY
    medication_type
),

late_counts AS (
  SELECT
    medication_type,
    COUNT(DISTINCT subject_id) AS patient_count,
    COUNT(DISTINCT hadm_id) AS admission_count
  FROM
    late_meds
  WHERE
    medication_type IN ('Insulin', 'Oral Agent')
  GROUP BY
    medication_type
),

-- Total patients in cohort
total_patients AS (
  SELECT
    COUNT(DISTINCT subject_id) AS total_subjects,
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM
    patient_cohort
)

-- Final results
SELECT
  'Early (0-48h)' AS time_period,
  ec.medication_type,
  ec.patient_count,
  ROUND(ec.patient_count * 100.0 / tp.total_subjects, 2) AS initiation_rate_pct,
  NULL AS net_change_pp
FROM
  early_counts ec
CROSS JOIN
  total_patients tp

UNION ALL

SELECT
  'Late (final 72h)' AS time_period,
  lc.medication_type,
  lc.patient_count,
  ROUND(lc.patient_count * 100.0 / tp.total_subjects, 2) AS initiation_rate_pct,
  NULL AS net_change_pp
FROM
  late_counts lc
CROSS JOIN
  total_patients tp

UNION ALL

SELECT
  'Net Change' AS time_period,
  ec.medication_type,
  NULL AS patient_count,
  NULL AS initiation_rate_pct,
  ROUND((lc.patient_count - ec.patient_count) * 100.0 / tp.total_subjects, 2) AS net_change_pp
FROM
  early_counts ec
JOIN
  late_counts lc ON ec.medication_type = lc.medication_type
CROSS JOIN
  total_patients tp
ORDER BY
  time_period, medication_type;