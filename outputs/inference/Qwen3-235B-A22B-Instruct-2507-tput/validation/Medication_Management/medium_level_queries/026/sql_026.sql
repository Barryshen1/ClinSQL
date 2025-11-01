WITH patients_filtered AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.patients
  WHERE gender = 'F'
    AND anchor_age BETWEEN 38 AND 48
),

admissions_with_diagnoses AS (
  SELECT a.hadm_id, a.subject_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp`.admissions a
  INNER JOIN patients_filtered p ON a.subject_id = p.subject_id
  WHERE EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.hadm_id = a.hadm_id
      AND d.icd_code LIKE 'E11%'
      AND d.icd_version = 10
  )
  AND EXISTS (
    SELECT 1
    FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses d
      ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
    WHERE di.hadm_id = a.hadm_id
      AND d.icd_code LIKE 'I50%'
      AND d.icd_version = 10
  )
),

antidiabetic_meds AS (
  SELECT p.hadm_id,
    p.starttime,
    CASE
      WHEN REGEXP_CONTAINS(LOWER(p.drug), r'insulin|lantus|levemir|novolog|humalog|apidra|toujeo|basaglar|admelog|fiasp')
        THEN 'insulin'
      WHEN LOWER(p.drug) IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'saxagliptin',
        'linagliptin', 'pioglitazone', 'rosiglitazone', 'acarbose', 'miglitol', 'repaglinide', 'nateglinide'
      )
        THEN 'oral'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp`.prescriptions p
  INNER JOIN admissions_with_diagnoses a ON p.hadm_id = a.hadm_id
  WHERE p.starttime IS NOT NULL
    AND (
      REGEXP_CONTAINS(LOWER(p.drug), r'insulin|lantus|levemir|novolog|humalog|apidra|toujeo|basaglar|admelog|fiasp')
      OR LOWER(p.drug) IN (
        'metformin', 'glipizide', 'glyburide', 'glimepiride', 'sitagliptin', 'saxagliptin',
        'linagliptin', 'pioglitazone', 'rosiglitazone', 'acarbose', 'miglitol', 'repaglinide', 'nateglinide'
      )
    )
),

first_admin_times AS (
  SELECT hadm_id,
    MIN(CASE WHEN drug_class = 'insulin' THEN starttime END) AS first_insulin_time,
    MIN(CASE WHEN drug_class = 'oral' THEN starttime END) AS first_oral_time
  FROM antidiabetic_meds
  GROUP BY hadm_id
),

initiation_timing AS (
  SELECT a.hadm_id,
    a.admittime,
    a.dischtime,
    CASE
      WHEN f.first_insulin_time IS NOT NULL
       AND f.first_insulin_time >= a.admittime
       AND f.first_insulin_time <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 END AS initiated_insulin_first_72h,
    CASE
      WHEN f.first_insulin_time IS NOT NULL
       AND f.first_insulin_time >= DATETIME_SUB(a.dischtime, INTERVAL 72 HOUR)
       AND f.first_insulin_time <= a.dischtime
      THEN 1 ELSE 0 END AS initiated_insulin_last_72h,
    CASE
      WHEN f.first_oral_time IS NOT NULL
       AND f.first_oral_time >= a.admittime
       AND f.first_oral_time <= DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
      THEN 1 ELSE 0 END AS initiated_oral_first_72h,
    CASE
      WHEN f.first_oral_time IS NOT NULL
       AND f.first_oral_time >= DATETIME_SUB(a.dischtime, INTERVAL 72 HOUR)
       AND f.first_oral_time <= a.dischtime
      THEN 1 ELSE 0 END AS initiated_oral_last_72h
  FROM admissions_with_diagnoses a
  LEFT JOIN first_admin_times f ON a.hadm_id = f.hadm_id
)

SELECT
  ROUND(100.0 * SUM(initiated_insulin_first_72h) / COUNT(*), 2) AS pct_insulin_initiated_first_72h,
  ROUND(100.0 * SUM(initiated_oral_first_72h) / COUNT(*), 2) AS pct_oral_initiated_first_72h,
  ROUND(100.0 * SUM(initiated_insulin_last_72h) / COUNT(*), 2) AS pct_insulin_initiated_last_72h,
  ROUND(100.0 * SUM(initiated_oral_last_72h) / COUNT(*), 2) AS pct_oral_initiated_last_72h
FROM initiation_timing;