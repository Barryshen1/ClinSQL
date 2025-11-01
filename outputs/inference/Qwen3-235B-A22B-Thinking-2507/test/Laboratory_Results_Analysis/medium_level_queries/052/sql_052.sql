WITH cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 76 AND 86
    AND a.hadm_id IN (
      SELECT hadm_id 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.seq_num = 1
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '410%')
          OR (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'I22%'))
        )
    )
),
first_troponin AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` d
    ON l.itemid = d.itemid
  WHERE d.label = 'Troponin I'
    AND l.valuenum IS NOT NULL
),
troponin_data AS (
  SELECT 
    c.hadm_id,
    c.age,
    t.valuenum,
    CASE 
      WHEN t.valuenum <= 0.04 THEN 'normal'
      WHEN t.valuenum > 0.04 AND t.valuenum <= 0.40 THEN 'borderline'
      WHEN t.valuenum > 0.40 THEN 'elevated'
    END AS category
  FROM cohort c
  INNER JOIN first_troponin t
    ON c.hadm_id = t.hadm_id
  WHERE t.rn = 1
),
category_counts AS (
  SELECT 
    category,
    COUNT(*) AS count,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS percentage
  FROM troponin_data
  GROUP BY category
),
summary_stats AS (
  SELECT 
    AVG(valuenum) AS mean,
    APPROX_QUANTILES(valuenum, 1000)[OFFSET(500)] AS median,
    APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS iqr
  FROM troponin_data
)
SELECT 
  cc.category,
  cc.count,
  ROUND(cc.percentage, 2) AS percentage,
  ss.mean,
  ss.median,
  ss.iqr
FROM category_counts cc
CROSS JOIN summary_stats ss
ORDER BY 
  CASE cc.category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;