WITH eligible_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.anchor_age,
    p.gender
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di1
    ON a.hadm_id = di1.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
    ON a.hadm_id = di2.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      (d1.long_title LIKE '%diabetes mellitus, type 2%' OR di1.icd_code LIKE 'E11%')
      AND
      (d2.long_title LIKE '%heart failure%' OR di2.icd_code LIKE 'I50%')
    )
),
prescriptions_in_window AS (
  SELECT
    ea.subject_id,
    ea.hadm_id,
    p.starttime,
    p.drug,
    CASE
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%gliclazide%' OR LOWER(p.drug) LIKE '%glimepiride%' OR LOWER(p.drug) LIKE '%tolbutamide%' OR LOWER(p.drug) LIKE '%chlorpropamide%' THEN 'sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' OR LOWER(p.drug) LIKE '%vildagliptin%' THEN 'dpp4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' OR LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' THEN 'sglt2'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'tzd'
      ELSE NULL
    END AS drug_class
  FROM eligible_admissions ea
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` p
    ON ea.hadm_id = p.hadm_id
  WHERE p.starttime >= ea.admittime
    AND p.starttime <= ea.dischtime
    AND p.drug IS NOT NULL
    AND p.drug != ''
),
class_counts AS (
  SELECT
    pw.drug_class,
    COUNT(DISTINCT CASE 
      WHEN pw.starttime BETWEEN ea.admittime AND ea.admittime + INTERVAL '72' HOUR 
      THEN pw.subject_id 
    END) AS n_first72h,
    COUNT(DISTINCT CASE 
      WHEN pw.starttime BETWEEN ea.dischtime - INTERVAL '48' HOUR AND ea.dischtime 
      THEN pw.subject_id 
    END) AS n_final48h,
    COUNT(DISTINCT pw.subject_id) AS total_patients
  FROM prescriptions_in_window pw
  JOIN eligible_admissions ea 
    ON pw.subject_id = ea.subject_id AND pw.hadm_id = ea.hadm_id
  WHERE pw.drug_class IS NOT NULL
  GROUP BY pw.drug_class
)
SELECT
  drug_class,
  ROUND(100.0 * n_first72h / total_patients, 2) AS prevalence_first72h_pct,
  ROUND(100.0 * n_final48h / total_patients, 2) AS prevalence_final48h_pct,
  ROUND(100.0 * (n_first72h - n_final48h) / total_patients, 2) AS pp_difference
FROM class_counts
ORDER BY drug_class;