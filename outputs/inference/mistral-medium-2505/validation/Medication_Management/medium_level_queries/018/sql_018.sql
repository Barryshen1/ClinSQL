WITH
-- Get female patients aged 81-91 with T2DM and heart failure
patient_cohort AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d1 ON a.subject_id = d1.subject_id AND a.hadm_id = d1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2 ON a.subject_id = d2.subject_id AND a.hadm_id = d2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd1 ON d1.icd_code = icd1.icd_code AND d1.icd_version = icd1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd2 ON d2.icd_code = icd2.icd_code AND d2.icd_version = icd2.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (icd1.icd_code LIKE 'E11%' OR icd1.icd_code LIKE 'E11.%') -- T2DM
    AND (icd2.icd_code LIKE 'I50%' OR icd2.icd_code LIKE 'I50.%') -- Heart failure
    AND d1.seq_num = 1 -- Primary diagnosis for T2DM
    AND d2.seq_num = 1 -- Primary diagnosis for heart failure
),

-- Get all admissions for these patients
admissions_data AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR) AS admission_duration_hours
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN patient_cohort pc ON a.subject_id = pc.subject_id
  WHERE a.admission_type NOT IN ('EMERGENCY', 'NEWBORN')
),

-- Get all prescriptions for these admissions
prescriptions_data AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.stoptime,
    p.drug,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'Sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' THEN 'DPP4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' THEN 'SGLT2'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN admissions_data a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE p.drug_type = 'oral'
    AND p.drug IS NOT NULL
),

-- Calculate first 72h window (from admission to admission + 72h)
first_72h AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug_class,
    COUNT(DISTINCT p.subject_id) AS patient_count
  FROM prescriptions_data p
  JOIN admissions_data a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE p.starttime <= TIMESTAMP_ADD(a.admittime, INTERVAL 72 HOUR)
    AND (p.stoptime IS NULL OR p.stoptime >= a.admittime)
    AND p.drug_class IS NOT NULL
  GROUP BY p.subject_id, p.hadm_id, p.drug_class
),

-- Calculate final 48h window (from discharge - 48h to discharge)
final_48h AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.drug_class,
    COUNT(DISTINCT p.subject_id) AS patient_count
  FROM prescriptions_data p
  JOIN admissions_data a ON p.subject_id = a.subject_id AND p.hadm_id = a.hadm_id
  WHERE p.starttime <= a.dischtime
    AND (p.stoptime IS NULL OR p.stoptime >= TIMESTAMP_SUB(a.dischtime, INTERVAL 48 HOUR))
    AND p.drug_class IS NOT NULL
    AND a.admission_duration_hours >= 48 -- Only include admissions long enough for final 48h window
  GROUP BY p.subject_id, p.hadm_id, p.drug_class
),

-- Count total patients in cohort
total_patients AS (
  SELECT COUNT(DISTINCT subject_id) AS total_count
  FROM patient_cohort
)

-- Final results
SELECT
  COALESCE(f.drug_class, l.drug_class) AS drug_class,
  -- First 72h prevalence
  ROUND(COUNT(DISTINCT f.subject_id) * 100.0 / (SELECT total_count FROM total_patients), 2) AS first_72h_prevalence,
  -- Final 48h prevalence
  ROUND(COUNT(DISTINCT l.subject_id) * 100.0 / (SELECT total_count FROM total_patients), 2) AS final_48h_prevalence,
  -- Absolute percentage point difference
  ROUND(
    (COUNT(DISTINCT l.subject_id) * 100.0 / (SELECT total_count FROM total_patients)) -
    (COUNT(DISTINCT f.subject_id) * 100.0 / (SELECT total_count FROM total_patients)),
    2
  ) AS abs_pp_diff
FROM first_72h f
FULL OUTER JOIN final_48h l ON f.drug_class = l.drug_class AND f.subject_id = l.subject_id
WHERE COALESCE(f.drug_class, l.drug_class) IS NOT NULL
GROUP BY COALESCE(f.drug_class, l.drug_class)
ORDER BY drug_class;