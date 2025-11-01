WITH cohort AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND a.admission_type != 'NEWBORN'
),

total_admissions AS (
  SELECT COUNT(DISTINCT hadm_id) AS total_hadms
  FROM cohort
),

first_48h_prescriptions AS (
  SELECT DISTINCT 
    c.hadm_id,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
    END AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= c.admittime 
    AND pr.starttime < c.admittime + INTERVAL 48 HOUR
    AND CASE 
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
    END IS NOT NULL
),

last_12h_prescriptions AS (
  SELECT DISTINCT 
    c.hadm_id,
    CASE 
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
    END AS drug_class
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id 
    AND c.hadm_id = pr.hadm_id
  WHERE pr.starttime IS NOT NULL
    AND pr.starttime >= c.dischtime - INTERVAL 12 HOUR 
    AND pr.starttime < c.dischtime
    AND CASE 
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%glipizide%' OR LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glimepiride%' THEN 'Sulfonylureas'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%' OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%' THEN 'DPP-4 Inhibitors'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%' OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%' THEN 'SGLT2 Inhibitors'
    END IS NOT NULL
),

first_48h_counts AS (
  SELECT 
    drug_class,
    COUNT(DISTINCT hadm_id) AS num_hadms_first48
  FROM first_48h_prescriptions
  GROUP BY drug_class
),

last_12h_counts AS (
  SELECT 
    drug_class,
    COUNT(DISTINCT hadm_id) AS num_hadms_last12
  FROM last_12h_prescriptions
  GROUP BY drug_class
)

SELECT 
  COALESCE(f.drug_class, l.drug_class) AS drug_class,
  ROUND(CAST((f.num_hadms_first48 / t.total_hadms * 100) AS NUMERIC), 2) AS first_48h_prevalence_pct,
  ROUND(CAST((l.num_hadms_last12 / t.total_hadms * 100) AS NUMERIC), 2) AS last_12h_prevalence_pct,
  ROUND(CAST(((l.num_hadms_last12 / t.total_hadms * 100) - (f.num_hadms_first48 / t.total_hadms * 100)) AS NUMERIC), 2) AS net_change_pp
FROM first_48h_counts f
FULL OUTER JOIN last_12h_counts l 
  ON f.drug_class = l.drug_class
CROSS JOIN total_admissions t
ORDER BY drug_class;