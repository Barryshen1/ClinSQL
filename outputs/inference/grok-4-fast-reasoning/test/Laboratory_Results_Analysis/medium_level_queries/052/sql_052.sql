WITH cohort AS (
  SELECT DISTINCT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
    AND d.seq_num = 1
    AND (
      (d.icd_version = '9' AND d.icd_code LIKE '410%')
      OR
      (d.icd_version = '10' AND d.icd_code LIKE 'I21%')
    )
),
troponin_itemids AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(REPLACE(label, '-', ' ')) LIKE '%troponin i%'
),
first_troponin AS (
  SELECT c.hadm_id, l.valuenum
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON c.hadm_id = l.hadm_id
  INNER JOIN troponin_itemids ti
    ON l.itemid = ti.itemid
  WHERE l.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY l.charttime ASC) = 1
),
total_count AS (
  SELECT COUNT(*) AS n FROM first_troponin
),
distribution AS (
  SELECT
    CASE
      WHEN valuenum <= 0.04 THEN 'Normal (≤0.04)'
      WHEN valuenum <= 0.40 THEN 'Borderline (0.04–0.40)'
      ELSE 'Elevated (≥0.40)'
    END AS category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT n FROM total_count), 2) AS percentage,
    NULL AS mean_val,
    NULL AS median_val,
    NULL AS iqr_min,
    NULL AS iqr_max
  FROM first_troponin
  GROUP BY 1
),
overall_stats AS (
  SELECT
    'Overall' AS category,
    (SELECT n FROM total_count) AS count,
    100.0 AS percentage,
    ROUND(AVG(valuenum), 4) AS mean_val,
    PERCENTILE_CONT(valuenum, 0.5) OVER() AS median_val,
    PERCENTILE_CONT(valuenum, 0.25) OVER() AS iqr_min,
    PERCENTILE_CONT(valuenum, 0.75) OVER() AS iqr_max
  FROM first_troponin
)
SELECT * FROM distribution
UNION ALL
SELECT * FROM overall_stats
ORDER BY CASE WHEN category = 'Overall' THEN 2 ELSE 1 END, category;