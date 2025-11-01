WITH cohort AS (
  SELECT 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.hadm_id IN (
      SELECT d.hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd
        ON d.icd_code = d_icd.icd_code AND d.icd_version = d_icd.icd_version
      WHERE (d_icd.long_title LIKE '%diabetes mellitus type 2%' OR d.icd_code LIKE 'E11%')
        AND d.hadm_id IN (
          SELECT d2.hadm_id
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d2
          JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d_icd2
            ON d2.icd_code = d_icd2.icd_code AND d2.icd_version = d_icd2.icd_version
          WHERE (d_icd2.long_title LIKE '%heart failure%' OR d2.icd_code LIKE 'I50%')
        )
    )
),
prescriptions_with_class AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    c.admittime,
    c.dischtime,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%gliclazide%' THEN 'sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' THEN 'sglt2'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'tzd'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  JOIN cohort c ON p.hadm_id = c.hadm_id
  WHERE p.drug IS NOT NULL
    AND (p.route = 'Oral' OR p.route = 'PO')
),
time_flags AS (
  SELECT 
    hadm_id,
    drug_class,
    CASE 
      WHEN starttime BETWEEN admittime AND admittime + INTERVAL '72' HOUR THEN 1 
      ELSE 0 
    END AS first_72h,
    CASE 
      WHEN starttime BETWEEN dischtime - INTERVAL '48' HOUR AND dischtime THEN 1 
      ELSE 0 
    END AS final_48h
  FROM prescriptions_with_class
  WHERE drug_class IS NOT NULL
),
patient_class_flags AS (
  SELECT 
    hadm_id,
    drug_class,
    MAX(first_72h) AS first_72h_flag,
    MAX(final_48h) AS final_48h_flag
  FROM time_flags
  GROUP BY hadm_id, drug_class
),
total_patients AS (
  SELECT COUNT(DISTINCT hadm_id) AS total
  FROM cohort
)
SELECT 
  drug_class,
  ROUND(SUM(first_72h_flag) * 100.0 / (SELECT total FROM total_patients), 2) AS first_72h_prevalence,
  ROUND(SUM(final_48h_flag) * 100.0 / (SELECT total FROM total_patients), 2) AS final_48h_prevalence,
  ROUND((SUM(first_72h_flag) - SUM(final_48h_flag)) * 100.0 / (SELECT total FROM total_patients), 2) AS abs_diff
FROM patient_class_flags
GROUP BY drug_class;