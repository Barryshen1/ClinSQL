WITH
-- Get male patients aged 66-76
eligible_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 66 AND 76
),

-- Get admissions with diabetes and heart failure
diabetes_hf_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS los_hours
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    eligible_patients p ON a.subject_id = p.subject_id
  WHERE
    EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
        ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
      WHERE d.subject_id = a.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          -- Diabetes ICD codes (E11.x, E13.x, etc.)
          di.icd_code LIKE 'E11%' OR di.icd_code LIKE 'E13%'
          -- Heart failure ICD codes (I50.x)
          OR di.icd_code LIKE 'I50%'
        )
    )
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) >= 72
),

-- Define antidiabetic classes
antidiabetic_classes AS (
  SELECT
    'Insulin' AS drug_class,
    'insulin' AS search_term UNION ALL
  SELECT
    'Metformin',
    'metformin' UNION ALL
  SELECT
    'Sulfonylureas',
    'sulfonylurea' UNION ALL
  SELECT
    'DPP-4 Inhibitors',
    'gliptin' UNION ALL
  SELECT
    'GLP-1 Agonists',
    'GLP-1' UNION ALL
  SELECT
    'SGLT2 Inhibitors',
    'gliflozin' UNION ALL
  SELECT
    'Thiazolidinediones',
    'glitazone'
),

-- Get prescriptions in first 72 hours
first_72h_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    ac.drug_class,
    COUNT(DISTINCT p.pharmacy_id) AS prescription_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    diabetes_hf_admissions a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN
    antidiabetic_classes ac ON LOWER(p.drug) LIKE '%' || LOWER(ac.search_term) || '%'
  WHERE
    p.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
  GROUP BY
    p.subject_id, p.hadm_id, ac.drug_class
),

-- Get prescriptions in final 24 hours
final_24h_prescriptions AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    ac.drug_class,
    COUNT(DISTINCT p.pharmacy_id) AS prescription_count
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    diabetes_hf_admissions a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  JOIN
    antidiabetic_classes ac ON LOWER(p.drug) LIKE '%' || LOWER(ac.search_term) || '%'
  WHERE
    p.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 24 HOUR) AND a.dischtime
  GROUP BY
    p.subject_id, p.hadm_id, ac.drug_class
),

-- Count patients with each drug class in each period
drug_class_counts AS (
  SELECT
    ac.drug_class,
    COUNT(DISTINCT CASE WHEN f.subject_id IS NOT NULL THEN f.subject_id END) AS first_72h_patients,
    COUNT(DISTINCT CASE WHEN l.subject_id IS NOT NULL THEN l.subject_id END) AS final_24h_patients,
    COUNT(DISTINCT a.subject_id) AS total_patients
  FROM
    diabetes_hf_admissions a
  CROSS JOIN
    antidiabetic_classes ac
  LEFT JOIN
    first_72h_prescriptions f ON a.subject_id = f.subject_id AND ac.drug_class = f.drug_class
  LEFT JOIN
    final_24h_prescriptions l ON a.subject_id = l.subject_id AND ac.drug_class = l.drug_class
  GROUP BY
    ac.drug_class
)

-- Calculate percentages
SELECT
  drug_class,
  ROUND(100 * first_72h_patients / total_patients, 1) AS first_72h_percentage,
  ROUND(100 * final_24h_patients / total_patients, 1) AS final_24h_percentage
FROM
  drug_class_counts
ORDER BY
  drug_class;