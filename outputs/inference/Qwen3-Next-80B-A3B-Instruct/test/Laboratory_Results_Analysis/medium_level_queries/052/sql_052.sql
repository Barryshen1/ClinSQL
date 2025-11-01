WITH eligible_patients AS (
  SELECT p.subject_id, p.hadm_id, p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
    ON p.subject_id = di.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND di.icd_version = 10
    AND di.icd_code LIKE 'I21%'
),

first_troponin_i AS (
  SELECT 
    ep.subject_id,
    ep.hadm_id,
    le.valuenum,
    le.charttime,
    ROW_NUMBER() OVER (PARTITION BY ep.subject_id, ep.hadm_id ORDER BY le.charttime) AS rn
  FROM eligible_patients ep
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.labevents le
    ON ep.subject_id = le.subject_id AND ep.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp`.d_labitems dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin i%'
    AND le.valuenum IS NOT NULL
),

categorized_troponin AS (
  SELECT 
    subject_id,
    hadm_id,
    valuenum,
    CASE 
      WHEN valuenum <= 0.04 THEN 'Normal (≤0.04)'
      WHEN valuenum < 0.40 THEN 'Borderline (0.04–0.40)'
      ELSE 'Elevated (≥0.40)'
    END AS category
  FROM first_troponin_i
  WHERE rn = 1
),

overall_stats AS (
  SELECT 
    AVG(valuenum) AS mean,
    PERCENTILE_CONT(valuenum, 0.5) AS median,
    PERCENTILE_CONT(valuenum, 0.25) AS q1,
    PERCENTILE_CONT(valuenum, 0.75) AS q3,
    PERCENTILE_CONT(valuenum, 0.75) - PERCENTILE_CONT(valuenum, 0.25) AS iqr
  FROM categorized_troponin
)

SELECT 
  ct.category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage,
  os.mean,
  os.median,
  os.iqr
FROM categorized_troponin ct
CROSS JOIN overall_stats os
GROUP BY ct.category, os.mean, os.median, os.iqr
ORDER BY ct.category;