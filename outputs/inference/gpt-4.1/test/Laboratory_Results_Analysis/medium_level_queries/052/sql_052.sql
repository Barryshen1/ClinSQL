with AMI
WITH ami_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 76 AND 86
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
    )
),
troponin_i_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),
first_troponin_i AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.anchor_age,
    aa.gender,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY le.charttime) AS rn
  FROM ami_admissions aa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.subject_id = le.subject_id AND aa.hadm_id = le.hadm_id
  JOIN troponin_i_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
),
categorized AS (
  SELECT
    subject_id,
    hadm_id,
    anchor_age,
    gender,
    charttime,
    valuenum,
    CASE
      WHEN valuenum <= 0.04 THEN 'Normal'
      WHEN valuenum > 0.04 AND valuenum < 0.40 THEN 'Borderline'
      WHEN valuenum >= 0.40 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_category
  FROM first_troponin_i
  WHERE rn = 1
),
stats AS (
  SELECT
    troponin_category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
  FROM categorized
  GROUP BY troponin_category
),
summary_stats AS (
  SELECT
    ROUND(AVG(valuenum), 3) AS mean,
    ROUND(APPROX_QUANTILES(valuenum, 2)[OFFSET(1)], 3) AS median,
    ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 3) AS iqr_25,
    ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 3) AS iqr_75
  FROM categorized
)
SELECT
  troponin_category,
  count,
  percentage,
  NULL AS mean,
  NULL AS median,
  NULL AS iqr_25,
  NULL AS iqr_75
FROM stats

UNION ALL

SELECT
  'Mean' AS troponin_category,
  NULL AS count,
  NULL AS percentage,
  mean,
  NULL AS median,
  NULL AS iqr_25,
  NULL AS iqr_75
FROM summary_stats

UNION ALL

SELECT
  'Median' AS troponin_category,
  NULL AS count,
  NULL AS percentage,
  NULL AS mean,
  median,
  NULL AS iqr_25,
  NULL AS iqr_75
FROM summary_stats

UNION ALL

SELECT
  'IQR_25' AS troponin_category,
  NULL AS count,
  NULL AS percentage,
  NULL AS mean,
  NULL AS median,
  iqr_25,
  NULL AS iqr_75
FROM summary_stats

UNION ALL

SELECT
  'IQR_75' AS troponin_category,
  NULL AS count,
  NULL AS percentage,
  NULL AS mean,
  NULL AS median,
  NULL AS iqr_25,
  iqr_75
FROM summary_stats
ORDER BY
  CASE
    WHEN troponin_category = 'Normal' THEN 1
    WHEN troponin_category = 'Borderline' THEN 2
    WHEN troponin_category = 'Elevated' THEN 3
    WHEN troponin_category = 'Mean' THEN 4
    WHEN troponin_category = 'Median' THEN 5
    WHEN troponin_category = 'IQR_25' THEN 6
    WHEN troponin_category = 'IQR_75' THEN 7
    ELSE 99
  END;

-- Target patient (81-year-old male) first Troponin I value and category
WITH ami_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    pat.anchor_age,
    pat.gender
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
      ON adm.hadm_id = diag.hadm_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age = 81
    AND (
      (diag.icd_version = 9 AND diag.icd_code LIKE '410%')
      OR (diag.icd_version = 10 AND (diag.icd_code LIKE 'I21%' OR diag.icd_code LIKE 'I22%'))
    )
),
troponin_i_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin i%'
),
first_troponin_i AS (
  SELECT
    aa.subject_id,
    aa.hadm_id,
    aa.anchor_age,
    aa.gender,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY aa.hadm_id ORDER BY le.charttime) AS rn
  FROM ami_admissions aa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON aa.subject_id = le.subject_id AND aa.hadm_id = le.hadm_id
  JOIN troponin_i_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
)
SELECT
  subject_id,
  hadm_id,
  anchor_age,
  gender,
  charttime,
  valuenum AS first_troponin_i,
  CASE
    WHEN valuenum <= 0.04 THEN 'Normal'
    WHEN valuenum > 0.04 AND valuenum < 0.40 THEN 'Borderline'
    WHEN valuenum >= 0.40 THEN 'Elevated'
    ELSE 'Unknown'
  END AS troponin_category
FROM first_troponin_i
WHERE rn = 1
LIMIT 1;