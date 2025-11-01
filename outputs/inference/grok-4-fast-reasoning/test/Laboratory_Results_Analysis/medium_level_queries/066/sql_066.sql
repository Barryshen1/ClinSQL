WITH cohort AS (
  SELECT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
    AND (
      (d.icd_version = '10' AND d.icd_code LIKE 'R07%')
      OR (d.icd_version = '9' AND d.icd_code LIKE '786.5%')
    )
),
initial_tnt AS (
  SELECT 
    l.hadm_id, 
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN cohort c ON l.hadm_id = c.hadm_id
  WHERE l.itemid = 503626
    AND l.valuenum IS NOT NULL
)
SELECT 
  category,
  COUNT(*) AS n,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage,
  ROUND(AVG(hs_tnt), 2) AS mean_hs_tnt_ngL,
  PERCENTILE_CONT(hs_tnt, 0.5) AS median_hs_tnt_ngL,
  PERCENTILE_CONT(hs_tnt, 0.75) - PERCENTILE_CONT(hs_tnt, 0.25) AS iqr_hs_tnt_ngL
FROM (
  SELECT 
    valuenum,
    CASE 
      WHEN valuenum * 1000 < 14 THEN 'normal'
      WHEN valuenum * 1000 <= 52 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS category,
    valuenum * 1000 AS hs_tnt
  FROM initial_tnt
  WHERE rn = 1
)
GROUP BY category
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1 
    WHEN 'borderline' THEN 2 
    ELSE 3 
  END;