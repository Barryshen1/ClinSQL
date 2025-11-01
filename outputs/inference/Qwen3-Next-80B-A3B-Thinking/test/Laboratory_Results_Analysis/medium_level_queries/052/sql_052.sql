WITH ami_admissions AS (
  SELECT a.hadm_id, a.subject_id, a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '410%')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'I21%')
    )
),
patients_ami AS (
  SELECT 
    a.hadm_id, 
    p.gender, 
    p.anchor_age, 
    p.anchor_year,
    a.admittime,
    p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year AS age_at_admission
  FROM ami_admissions a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 76 AND 86
),
troponin_events AS (
  SELECT 
    l.hadm_id, 
    l.charttime, 
    l.valuenum
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON l.hadm_id = a.hadm_id
  WHERE d.label LIKE '%TROPONIN I%'
    AND l.charttime BETWEEN a.admittime AND a.dischtime
    AND l.valuenum IS NOT NULL
),
first_troponin AS (
  SELECT 
    hadm_id, 
    valuenum,
    ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime) AS rn
  FROM troponin_events
),
first_troponin_ami AS (
  SELECT t.valuenum
  FROM first_troponin t
  JOIN patients_ami p
    ON t.hadm_id = p.hadm_id
  WHERE t.rn = 1
),
categorized AS (
  SELECT 
    CASE 
      WHEN valuenum <= 0.04 THEN 'normal'
      WHEN valuenum > 0.04 AND valuenum <= 0.40 THEN 'borderline'
      ELSE 'elevated'
    END AS category,
    valuenum
  FROM first_troponin_ami
),
category_counts AS (
  SELECT 
    category,
    COUNT(*) AS count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage
  FROM categorized
  GROUP BY category
),
summary_stats AS (
  SELECT 
    AVG(valuenum) AS mean,
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
    PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
  FROM categorized
)
SELECT 
  category,
  count,
  percentage,
  NULL AS mean,
  NULL AS median,
  NULL AS iqr
FROM category_counts
UNION ALL
SELECT 
  'summary' AS category,
  NULL AS count,
  NULL AS percentage,
  mean,
  median,
  iqr
FROM summary_stats;