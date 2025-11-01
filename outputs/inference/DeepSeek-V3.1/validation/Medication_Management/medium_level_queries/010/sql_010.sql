WITH cohort AS (
  -- Get female patients aged 67-77 with T2DM and HF
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 67 AND 77
    AND a.hadm_id IN (
      -- T2DM diagnoses
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
      WHERE (icd_version = 9 AND icd_code LIKE '250%' AND (icd_code LIKE '%0' OR icd_code LIKE '%2'))
         OR (icd_version = 10 AND icd_code LIKE 'E11%')
      INTERSECT DISTINCT
      -- HF diagnoses
      SELECT hadm_id FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
      WHERE (icd_version = 9 AND icd_code LIKE '428%')
         OR (icd_version = 10 AND (icd_code LIKE 'I50%' OR icd_code IN ('I11.0', 'I13.0', 'I13.2')))
    )
),

drug_classes AS (
  -- Map drug names to classes
  SELECT subject_id, hadm_id, starttime, drug,
    CASE
      WHEN LOWER(drug) LIKE '%insulin%' THEN 'insulin'
      WHEN LOWER(drug) LIKE '%metformin%' THEN 'met'
      WHEN LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%' THEN 'SU'
      WHEN LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%' THEN 'DPP-4'
      WHEN LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%' THEN 'SGLT2'
      WHEN LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%semaglutide%' THEN 'GLP-1'
      WHEN LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%' THEN 'TZD'
      ELSE NULL
    END AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE LOWER(drug) LIKE '%insulin%'
     OR LOWER(drug) LIKE '%metformin%'
     OR LOWER(drug) LIKE '%glipizide%' OR LOWER(drug) LIKE '%glyburide%' OR LOWER(drug) LIKE '%glimepiride%'
     OR LOWER(drug) LIKE '%sitagliptin%' OR LOWER(drug) LIKE '%saxagliptin%' OR LOWER(drug) LIKE '%linagliptin%' OR LOWER(drug) LIKE '%alogliptin%'
     OR LOWER(drug) LIKE '%canagliflozin%' OR LOWER(drug) LIKE '%dapagliflozin%' OR LOWER(drug) LIKE '%empagliflozin%'
     OR LOWER(drug) LIKE '%liraglutide%' OR LOWER(drug) LIKE '%dulaglutide%' OR LOWER(drug) LIKE '%exenatide%' OR LOWER(drug) LIKE '%semaglutide%'
     OR LOWER(drug) LIKE '%pioglitazone%' OR LOWER(drug) LIKE '%rosiglitazone%'
),

first_occurrences AS (
  -- For each patient and class, get the first starttime (initiation)
  SELECT subject_id, hadm_id, drug_class, MIN(starttime) AS first_start
  FROM drug_classes
  GROUP BY subject_id, hadm_id, drug_class
),

cohort_with_windows AS (
  -- Add time windows for each admission
  SELECT subject_id, hadm_id, admittime, dischtime,
    DATETIME_ADD(admittime, INTERVAL 12 HOUR) AS first_12h_end,
    DATETIME_SUB(dischtime, INTERVAL 48 HOUR) AS final_48h_start
  FROM cohort
),

initiation_first_12h AS (
  -- Check initiation in first 12h
  SELECT c.subject_id, c.hadm_id, f.drug_class,
    CASE WHEN f.first_start BETWEEN c.admittime AND c.first_12h_end THEN 1 ELSE 0 END AS initiated
  FROM cohort_with_windows c
  LEFT JOIN first_occurrences f
    ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
),

initiation_final_48h AS (
  -- Check initiation in final 48h
  SELECT c.subject_id, c.hadm_id, f.drug_class,
    CASE WHEN f.first_start BETWEEN c.final_48h_start AND c.dischtime THEN 1 ELSE 0 END AS initiated
  FROM cohort_with_windows c
  LEFT JOIN first_occurrences f
    ON c.subject_id = f.subject_id AND c.hadm_id = f.hadm_id
),

agg_first_12h AS (
  -- Aggregate by class for first 12h
  SELECT drug_class,
    COUNT(*) AS total_patients,
    SUM(initiated) AS initiated_count,
    ROUND(100.0 * SUM(initiated) / COUNT(*), 1) AS initiation_pct
  FROM initiation_first_12h
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class
),

agg_final_48h AS (
  -- Aggregate by class for final 48h
  SELECT drug_class,
    COUNT(*) AS total_patients,
    SUM(initiated) AS initiated_count,
    ROUND(100.0 * SUM(initiated) / COUNT(*), 1) AS initiation_pct
  FROM initiation_final_48h
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class
)

-- Combine and compute net change
SELECT 
  COALESCE(f.drug_class, l.drug_class) AS drug_class,
  COALESCE(f.initiation_pct, 0) AS first_12h_pct,
  COALESCE(l.initiation_pct, 0) AS final_48h_pct,
  COALESCE(l.initiation_pct, 0) - COALESCE(f.initiation_pct, 0) AS net_change_pp
FROM agg_first_12h f
FULL OUTER JOIN agg_final_48h l
  ON f.drug_class = l.drug_class
ORDER BY drug_class;