WITH
-- Define age range and gender
patient_base AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M'
    AND anchor_age BETWEEN 36 AND 46
),

-- Get admissions with T2DM and heart failure
admissions_with_conditions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    patient_base p ON a.subject_id = p.subject_id
  WHERE
    a.hospital_expire_flag = 0
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (di.icd_code LIKE 'E11%' OR dicd.long_title LIKE '%type 2 diabetes%')
    )
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
        ON di.icd_code = dicd.icd_code AND di.icd_version = dicd.icd_version
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND (di.icd_code LIKE 'I50%' OR dicd.long_title LIKE '%heart failure%')
    )
),

-- Define antidiabetic drug classes
antidiabetic_classes AS (
  SELECT
    drug,
    CASE
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' THEN 'DPP-4 inhibitors'
      WHEN LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%dulaglutide%' THEN 'GLP-1 agonists'
      WHEN LOWER(drug) LIKE '%empagliflozin%' OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' THEN 'SGLT2 inhibitors'
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'Insulin'
      ELSE 'Other'
    END AS drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions`
  GROUP BY
    drug
),

-- Get prescriptions with drug classes
prescriptions_with_classes AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug,
    ac.drug_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN
    antidiabetic_classes ac ON LOWER(p.drug) = LOWER(ac.drug)
),

-- First 12 hours window
first_12h_prescriptions AS (
  SELECT
    a.hadm_id,
    pwc.drug_class,
    COUNT(DISTINCT pwc.subject_id) AS patient_count
  FROM
    admissions_with_conditions a
  JOIN
    prescriptions_with_classes pwc ON a.hadm_id = pwc.hadm_id
  WHERE
    pwc.starttime BETWEEN a.admittime AND TIMESTAMP_ADD(a.admittime, INTERVAL 12 HOUR)
  GROUP BY
    a.hadm_id, pwc.drug_class
),

-- Final 48 hours window
final_48h_prescriptions AS (
  SELECT
    a.hadm_id,
    pwc.drug_class,
    COUNT(DISTINCT pwc.subject_id) AS patient_count
  FROM
    admissions_with_conditions a
  JOIN
    prescriptions_with_classes pwc ON a.hadm_id = pwc.hadm_id
  WHERE
    pwc.starttime BETWEEN TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR) AND a.dischtime
  GROUP BY
    a.hadm_id, pwc.drug_class
),

-- Total patients per admission
total_patients AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT subject_id) AS total_count
  FROM
    admissions_with_conditions
  GROUP BY
    hadm_id
)

-- Final comparison
SELECT
  COALESCE(f12h.drug_class, f48h.drug_class) AS drug_class,
  SUM(f12h.patient_count) AS first_12h_count,
  SUM(f48h.patient_count) AS final_48h_count,
  SUM(tp.total_count) AS total_admissions,
  ROUND(SUM(f12h.patient_count) * 100.0 / SUM(tp.total_count), 2) AS first_12h_percentage,
  ROUND(SUM(f48h.patient_count) * 100.0 / SUM(tp.total_count), 2) AS final_48h_percentage,
  ROUND((SUM(f48h.patient_count) - SUM(f12h.patient_count)) * 100.0 / SUM(tp.total_count), 2) AS net_change_pp
FROM
  first_12h_prescriptions f12h
FULL OUTER JOIN
  final_48h_prescriptions f48h ON f12h.hadm_id = f48h.hadm_id AND f12h.drug_class = f48h.drug_class
JOIN
  total_patients tp ON COALESCE(f12h.hadm_id, f48h.hadm_id) = tp.hadm_id
GROUP BY
  COALESCE(f12h.drug_class, f48h.drug_class)
ORDER BY
  net_change_pp DESC;