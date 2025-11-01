WITH
-- Define age range and gender
patient_demographics AS (
  SELECT
    subject_id,
    gender,
    anchor_age,
    anchor_year
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F'
    AND anchor_age BETWEEN 69 AND 79
),

-- Get admissions with T2DM and heart failure
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_demographics p ON a.subject_id = p.subject_id
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        a.hadm_id = d.hadm_id
        AND (
          -- T2DM codes
          d.icd_code LIKE 'E11%' OR
          d.icd_code LIKE 'E13%' OR
          d.icd_code LIKE 'E14%'
        )
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE
        a.hadm_id = d.hadm_id
        AND (
          -- Heart failure codes
          d.icd_code LIKE 'I50%' OR
          d.icd_code = 'I11.0' OR
          d.icd_code = 'I13.0' OR
          d.icd_code = 'I13.2'
        )
    )
),

-- Get all prescriptions for these patients
patient_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    p.drug_type,
    p.ndc,
    p.route,
    p.dose_val_rx,
    p.dose_unit_rx,
    p.doses_per_24_hrs
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    patient_admissions a ON p.hadm_id = a.hadm_id
),

-- Classify drugs into categories
drug_classification AS (
  SELECT
    subject_id,
    hadm_id,
    starttime,
    stoptime,
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%glimepiride%' OR
           LOWER(drug) LIKE '%glyburide%' OR
           LOWER(drug) LIKE '%glipizide%' THEN 'Sulfonylurea'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR
           LOWER(drug) LIKE '%saxagliptin%' OR
           LOWER(drug) LIKE '%linagliptin%' OR
           LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%empagliflozin%' OR
           LOWER(drug) LIKE '%canagliflozin%' OR
           LOWER(drug) LIKE '%dapagliflozin%' OR
           LOWER(drug) LIKE '%ertugliflozin%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%liraglutide%' OR
           LOWER(drug) LIKE '%semaglutide%' OR
           LOWER(drug) LIKE '%exenatide%' OR
           LOWER(drug) LIKE '%dulaglutide%' OR
           LOWER(drug) LIKE '%lixisenatide%' THEN 'GLP-1'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR
           LOWER(drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE 'Other'
    END AS drug_class
  FROM
    patient_prescriptions
  WHERE
    drug IS NOT NULL
),

-- Calculate first and last 72-hour windows for each admission
time_windows AS (
  SELECT
    hadm_id,
    admittime,
    dischtime,
    TIMESTAMP_ADD(admittime, INTERVAL 72 HOUR) AS first_72_end,
    TIMESTAMP_SUB(dischtime, INTERVAL 72 HOUR) AS last_72_start
  FROM
    patient_admissions
),

-- Check which drug classes were given in each time window
drug_usage AS (
  SELECT
    t.hadm_id,
    d.drug_class,
    -- First 72 hours
    MAX(CASE WHEN d.starttime BETWEEN t.admittime AND t.first_72_end THEN 1 ELSE 0 END) AS first_72,
    -- Last 72 hours
    MAX(CASE WHEN d.starttime BETWEEN t.last_72_start AND t.dischtime THEN 1 ELSE 0 END) AS last_72
  FROM
    time_windows t
  LEFT JOIN
    drug_classification d ON t.hadm_id = d.hadm_id
  GROUP BY
    t.hadm_id, d.drug_class
),

-- Pivot the results to get counts per drug class
drug_usage_pivot AS (
  SELECT
    drug_class,
    SUM(first_72) AS first_72_count,
    SUM(last_72) AS last_72_count,
    COUNT(DISTINCT hadm_id) AS total_admissions
  FROM
    drug_usage
  GROUP BY
    drug_class
)

-- Final calculation of percentages
SELECT
  drug_class,
  total_admissions,
  first_72_count,
  ROUND(first_72_count * 100.0 / total_admissions, 1) AS first_72_percent,
  last_72_count,
  ROUND(last_72_count * 100.0 / total_admissions, 1) AS last_72_percent
FROM
  drug_usage_pivot
WHERE
  drug_class IN ('Insulin', 'Metformin', 'Sulfonylurea', 'DPP-4', 'SGLT2', 'GLP-1', 'TZD')
ORDER BY
  drug_class;