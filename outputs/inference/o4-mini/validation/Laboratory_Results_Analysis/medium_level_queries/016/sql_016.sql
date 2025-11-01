WITH troponin_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),

-- Get the first troponin measurement per admission
initial_troponin AS (
  SELECT
    le.subject_id,
    le.hadm_id,
    le.valuenum AS troponin_value,
    ROW_NUMBER() OVER (PARTITION BY le.subject_id, le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
),

-- Filter to the first measurement only
first_trop AS (
  SELECT subject_id, hadm_id, troponin_value
  FROM initial_troponin
  WHERE rn = 1
),

-- Identify the target cohort: male, age 79–89, admitted
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 79 AND 89
),

-- Join cohort with first troponin
trop_data AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    f.troponin_value,
    CASE
      WHEN f.troponin_value <= 0.03 THEN 'normal'
      WHEN f.troponin_value <= 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM cohort c
  JOIN first_trop f
    ON c.subject_id = f.subject_id
   AND c.hadm_id = f.hadm_id
)

-- Final aggregation
SELECT
  category,
  COUNT(*) AS n,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS pct,
  ROUND(AVG(troponin_value), 3) AS mean_troponin,
  -- Compute quartiles: [0]=min, [1]=Q1, [2]=median, [3]=Q3, [4]=max
  APPROX_QUANTILES(troponin_value, 4)[OFFSET(2)] AS median_troponin,
  ROUND(
    APPROX_QUANTILES(troponin_value, 4)[OFFSET(3)]
    - APPROX_QUANTILES(troponin_value, 4)[OFFSET(1)], 
    3
  ) AS iqr_troponin
FROM trop_data
GROUP BY category
ORDER BY
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;