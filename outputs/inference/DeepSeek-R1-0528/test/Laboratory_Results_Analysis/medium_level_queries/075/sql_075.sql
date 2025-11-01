WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.anchor_age, 
    p.anchor_year, 
    p.gender,
    a.hadm_id, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
),
filtered_cohort AS (
  SELECT DISTINCT
    c.subject_id, 
    c.hadm_id
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON c.hadm_id = diag.hadm_id
  WHERE 
    (c.anchor_age + (EXTRACT(YEAR FROM c.admittime) - c.anchor_year)) BETWEEN 41 AND 51
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '7865%') 
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'R07%')
      OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I21%')
      OR (diag.icd_version = 10 AND diag.icd_code LIKE 'I22%')
    )
),
troponin_t_items AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems` 
  WHERE LOWER(label) LIKE '%troponin t%'
),
first_troponin AS (
  SELECT 
    fc.subject_id,
    fc.hadm_id,
    le.valuenum,
    le.ref_range_upper,
    le.flag
  FROM filtered_cohort fc
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fc.subject_id = le.subject_id 
    AND fc.hadm_id = le.hadm_id
  WHERE le.itemid IN (SELECT itemid FROM troponin_t_items)
    AND le.valuenum IS NOT NULL
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY fc.hadm_id 
    ORDER BY le.charttime
  ) = 1
),
categorized AS (
  SELECT 
    *,
    CASE 
      WHEN flag = 'Borderline' THEN 'borderline'
      WHEN flag IN ('High', 'Abnormal', 'Critical') OR valuenum > ref_range_upper THEN 'elevated'
      WHEN flag = 'Normal' OR valuenum <= ref_range_upper THEN 'normal'
    END AS category
  FROM first_troponin
  WHERE ref_range_upper IS NOT NULL OR flag IS NOT NULL
),
aggregated AS (
  SELECT 
    category,
    COUNT(*) AS n,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS percentage,
    AVG(valuenum) AS mean,
    APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM categorized
  WHERE category IS NOT NULL
  GROUP BY category
)
SELECT 
  category,
  n,
  percentage,
  mean,
  quantiles[SAFE_OFFSET(2)] AS median,
  quantiles[SAFE_OFFSET(3)] - quantiles[SAFE_OFFSET(1)] AS iqr
FROM aggregated
ORDER BY category;