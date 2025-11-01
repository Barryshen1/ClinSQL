WITH cohort AS (
  SELECT a.subject_id,
         a.hadm_id,
         p.anchor_age,
         p.gender,
         a.admittime,
         a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
),
drug_flags AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    CASE
      WHEN LOWER(pr.drug) LIKE '%metformin%' THEN 'Metformin'
      WHEN LOWER(pr.drug) LIKE '%glyburide%' OR LOWER(pr.drug) LIKE '%glipizide%' 
        OR LOWER(pr.drug) LIKE '%glimepiride%' OR LOWER(pr.drug) LIKE '%chlorpropamide%'
        OR LOWER(pr.drug) LIKE '%tolbutamide%' OR LOWER(pr.drug) LIKE '%tolazamide%'
        THEN 'Sulfonylureas'
      WHEN LOWER(pr.drug) LIKE '%sitagliptin%' OR LOWER(pr.drug) LIKE '%saxagliptin%'
        OR LOWER(pr.drug) LIKE '%linagliptin%' OR LOWER(pr.drug) LIKE '%alogliptin%'
        THEN 'DPP-4 inhibitors'
      WHEN LOWER(pr.drug) LIKE '%canagliflozin%' OR LOWER(pr.drug) LIKE '%dapagliflozin%'
        OR LOWER(pr.drug) LIKE '%empagliflozin%' OR LOWER(pr.drug) LIKE '%ertugliflozin%'
        THEN 'SGLT2 inhibitors'
      ELSE NULL
    END AS drug_class,
    -- first window flag
    CASE 
      WHEN pr.starttime IS NOT NULL
       AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
       AND (pr.stoptime IS NULL OR pr.stoptime >= c.admittime)
      THEN 1 ELSE 0 END AS in_first48h,
    -- last window flag
    CASE
      WHEN pr.starttime IS NOT NULL
       AND pr.starttime <= c.dischtime
       AND (pr.stoptime IS NULL OR pr.stoptime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR))
       AND pr.starttime >= TIMESTAMP_SUB(c.dischtime, INTERVAL 12 HOUR)
      THEN 1 ELSE 0 END AS in_last12h
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
),
agg_flags AS (
  SELECT
    drug_class,
    COUNT(DISTINCT CASE WHEN in_first48h = 1 THEN CONCAT(subject_id,'-',hadm_id) END) AS n_first48h,
    COUNT(DISTINCT CASE WHEN in_last12h = 1 THEN CONCAT(subject_id,'-',hadm_id) END) AS n_last12h,
    COUNT(DISTINCT CONCAT(subject_id,'-',hadm_id)) AS n_total
  FROM drug_flags
  WHERE drug_class IS NOT NULL
  GROUP BY drug_class
)
SELECT
  drug_class,
  ROUND(100.0 * n_first48h / n_total, 2) AS prevalence_first48h_pct,
  ROUND(100.0 * n_last12h / n_total, 2) AS prevalence_last12h_pct,
  ROUND(100.0 * n_last12h / n_total - 100.0 * n_first48h / n_total, 2) AS net_change_pp
FROM agg_flags
ORDER BY drug_class;