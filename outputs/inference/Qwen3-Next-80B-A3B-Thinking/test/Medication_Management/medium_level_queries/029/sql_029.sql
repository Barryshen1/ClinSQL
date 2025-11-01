WITH drug_classes AS (
  SELECT 'insulin' AS drug_class UNION ALL
  SELECT 'metformin' UNION ALL
  SELECT 'sulfonylurea' UNION ALL
  SELECT 'dpp4' UNION ALL
  SELECT 'sglt2' UNION ALL
  SELECT 'glp1' UNION ALL
  SELECT 'tzd'
),
cohort AS (
  SELECT t2dm.subject_id, t2dm.hadm_id
  FROM (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'E11%'
  ) t2dm
  INNER JOIN (
    SELECT subject_id, hadm_id
    FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
    WHERE icd_code LIKE 'I50%'
  ) hf ON t2dm.subject_id = hf.subject_id AND t2dm.hadm_id = hf.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON t2dm.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 69 AND 79
),
cohort_with_times AS (
  SELECT c.subject_id, c.hadm_id, a.admittime, a.dischtime
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON c.hadm_id = a.hadm_id
),
prescriptions_filtered AS (
  SELECT 
    p.hadm_id,
    p.starttime,
    CASE
      WHEN LOWER(p.drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(p.drug) LIKE '%metformin%' THEN 'metformin'
      WHEN LOWER(p.drug) LIKE '%glipizide%' OR LOWER(p.drug) LIKE '%glyburide%' OR LOWER(p.drug) LIKE '%glimepiride%' THEN 'sulfonylurea'
      WHEN LOWER(p.drug) LIKE '%sitagliptin%' OR LOWER(p.drug) LIKE '%saxagliptin%' OR LOWER(p.drug) LIKE '%linagliptin%' OR LOWER(p.drug) LIKE '%alogliptin%' THEN 'dpp4'
      WHEN LOWER(p.drug) LIKE '%canagliflozin%' OR LOWER(p.drug) LIKE '%dapagliflozin%' OR LOWER(p.drug) LIKE '%empagliflozin%' THEN 'sglt2'
      WHEN LOWER(p.drug) LIKE '%liraglutide%' OR LOWER(p.drug) LIKE '%exenatide%' OR LOWER(p.drug) LIKE '%semaglutide%' OR LOWER(p.drug) LIKE '%dulaglutide%' THEN 'glp1'
      WHEN LOWER(p.drug) LIKE '%pioglitazone%' OR LOWER(p.drug) LIKE '%rosiglitazone%' THEN 'tzd'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  INNER JOIN cohort_with_times cwt ON p.hadm_id = cwt.hadm_id
  WHERE p.drug IS NOT NULL
),
first_72 AS (
  SELECT 
    drug_class,
    cwt.hadm_id,
    MAX(CASE WHEN starttime BETWEEN admittime AND admittime + INTERVAL 72 HOUR THEN 1 ELSE 0 END) AS received_first
  FROM prescriptions_filtered
  INNER JOIN cohort_with_times cwt ON prescriptions_filtered.hadm_id = cwt.hadm_id
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class, cwt.hadm_id
),
last_72 AS (
  SELECT 
    drug_class,
    cwt.hadm_id,
    MAX(CASE WHEN starttime BETWEEN dischtime - INTERVAL 72 HOUR AND dischtime THEN 1 ELSE 0 END) AS received_last
  FROM prescriptions_filtered
  INNER JOIN cohort_with_times cwt ON prescriptions_filtered.hadm_id = cwt.hadm_id
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class, cwt.hadm_id
),
total_patients AS (
  SELECT COUNT(*) AS total
  FROM cohort
)
SELECT 
  dc.drug_class,
  COALESCE(SUM(f.received_first), 0) * 100.0 / t.total AS first_72_percent,
  COALESCE(SUM(l.received_last), 0) * 100.0 / t.total AS last_72_percent
FROM drug_classes dc
LEFT JOIN first_72 f ON dc.drug_class = f.drug_class
LEFT JOIN last_72 l ON dc.drug_class = l.drug_class
CROSS JOIN total_patients t
GROUP BY dc.drug_class, t.total;