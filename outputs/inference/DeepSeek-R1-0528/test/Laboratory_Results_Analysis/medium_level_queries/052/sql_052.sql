WITH ami_admissions AS (
  SELECT 
    adm.subject_id, 
    adm.hadm_id, 
    adm.admittime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    p.anchor_age + (EXTRACT(YEAR FROM adm.admittime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON adm.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      WHERE adm.hadm_id = diag.hadm_id
        AND ( 
          (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
          OR (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
        )
    )
),
filtered_admissions AS (
  SELECT *
  FROM ami_admissions
  WHERE age_at_admission BETWEEN 76 AND 86
),
troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),
troponin_events AS (
  SELECT 
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.valuenum,
    le.valueuom,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN troponin_items 
    ON le.itemid = troponin_items.itemid
  WHERE 
    le.valuenum IS NOT NULL
    AND le.valueuom = 'ng/mL'
),
first_troponin AS (
  SELECT 
    subject_id,
    hadm_id,
    valuenum AS troponin_value
  FROM troponin_events
  WHERE rn = 1
),
eligible_troponin AS (
  SELECT 
    ft.hadm_id,
    ft.troponin_value,
    CASE 
      WHEN ft.troponin_value <= 0.04 THEN 'Normal'
      WHEN ft.troponin_value <= 0.40 THEN 'Borderline'
      ELSE 'Elevated'
    END AS category
  FROM filtered_admissions fa
  INNER JOIN first_troponin ft
    ON fa.hadm_id = ft.hadm_id
),
total_count AS (
  SELECT COUNT(*) AS total
  FROM eligible_troponin  -- Fixed: Added FROM keyword
),
category_summary AS (
  SELECT 
    category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / (SELECT total FROM total_count), 2) AS percentage
  FROM eligible_troponin
  GROUP BY category
),
overall_stats AS (
  SELECT 
    AVG(troponin_value) AS mean,
    APPROX_QUANTILES(troponin_value, 100)[OFFSET(50)] AS median,
    APPROX_QUANTILES(troponin_value, 100)[OFFSET(75)] - APPROX_QUANTILES(troponin_value, 100)[OFFSET(25)] AS iqr
  FROM eligible_troponin
)
SELECT 
  category,
  count,
  percentage,
  NULL AS mean,
  NULL AS median,
  NULL AS iqr
FROM category_summary
UNION ALL
SELECT 
  'Overall' AS category,
  NULL AS count,
  NULL AS percentage,
  mean,
  median,
  iqr
FROM overall_stats
ORDER BY 
  CASE category
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;