WITH target_population AS (
  SELECT DISTINCT p.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di1
    ON a.hadm_id = di1.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d1
    ON di1.icd_code = d1.icd_code AND di1.icd_version = d1.icd_version
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di2
    ON a.hadm_id = di2.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d2
    ON di2.icd_code = d2.icd_code AND di2.icd_version = d2.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND d1.long_title LIKE '%Diabetes Mellitus, Type 2%'
    AND d2.long_title LIKE '%Heart Failure%'
    AND di1.icd_version = 10
    AND di2.icd_version = 10
    AND a.admittime IS NOT NULL
    AND a.dischtime IS NOT NULL
),

drug_classes AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    tp.admittime,
    tp.dischtime,
    CASE 
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'met'
      WHEN LOWER(p.drug) LIKE '%glipizide%' 
        OR LOWER(p.drug) LIKE '%glyburide%' 
        OR LOWER(p.drug) LIKE '%glimepiride%' 
        OR LOWER(p.drug) LIKE '%tolbutamide%' 
        OR LOWER(p.drug) LIKE '%chlorpropamide%' THEN 'su'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' 
        OR LOWER(p.drug) LIKE '%saxagliptin%' 
        OR LOWER(p.drug) LIKE '%linagliptin%' 
        OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(p.drug) LIKE '%empagliflozin%' 
        OR LOWER(p.drug) LIKE '%dapagliflozin%' 
        OR LOWER(p.drug) LIKE '%canagliflozin%' 
        OR LOWER(p.drug) LIKE '%ertugliflozin%' THEN 'sglt2'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' 
        OR LOWER(p.drug) LIKE '%semaglutide%' 
        OR LOWER(p.drug) LIKE '%exenatide%' 
        OR LOWER(p.drug) LIKE '%dulaglutide%' 
        OR LOWER(p.drug) LIKE '%lixisenatide%' THEN 'glp1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' 
        OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'tzd'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN target_population tp ON p.hadm_id = tp.hadm_id
  WHERE p.starttime >= tp.admittime
    AND p.starttime <= tp.dischtime
    AND p.drug IS NOT NULL
    AND p.drug != ''
),

first12h AS (
  SELECT 
    drug_class,
    COUNT(DISTINCT hadm_id) AS n_patients
  FROM drug_classes
  WHERE starttime BETWEEN admittime AND admittime + INTERVAL '12' HOUR
    AND drug_class IS NOT NULL
  GROUP BY drug_class
),

final48h AS (
  SELECT 
    drug_class,
    COUNT(DISTINCT hadm_id) AS n_patients
  FROM drug_classes
  WHERE starttime BETWEEN dischtime - INTERVAL '48' HOUR AND dischtime
    AND drug_class IS NOT NULL
  GROUP BY drug_class
),

total_patients AS (
  SELECT COUNT(*) AS total FROM target_population
)

SELECT 
  COALESCE(f.drug_class, ff.drug_class) AS drug_class,
  ROUND(100.0 * f.n_patients / t.total, 2) AS init_first12h_pct,
  ROUND(100.0 * ff.n_patients / t.total, 2) AS init_final48h_pct,
  ROUND(100.0 * (ff.n_patients - f.n_patients) / t.total, 2) AS net_change_pp
FROM first12h f
FULL OUTER JOIN final48h ff ON f.drug_class = ff.drug_class
CROSS JOIN total_patients t
ORDER BY drug_class;