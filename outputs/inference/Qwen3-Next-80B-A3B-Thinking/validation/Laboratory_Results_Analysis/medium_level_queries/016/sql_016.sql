WITH admitted_patients AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.admittime, 
    p.anchor_age, 
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id
  WHERE d.seq_num = 1
    AND d.icd_code IN (
      'I20.0', 'I21.0', 'I21.1', 'I21.2', 'I21.3', 'I21.4', 'I21.9', 'I24.0', 'I24.8'
    )
    AND p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 79 AND 89
),
first_troponin AS (
  SELECT 
    ap.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY ap.hadm_id ORDER BY l.charttime) AS rn
  FROM admitted_patients ap
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
    ON ap.hadm_id = l.hadm_id
  WHERE l.itemid = 50911
    AND l.charttime >= ap.admittime
    AND l.valuenum IS NOT NULL
),
categorized AS (
  SELECT 
    hadm_id,
    valuenum,
    CASE
      WHEN valuenum < 0.01 THEN 'normal'
      WHEN valuenum >= 0.01 AND valuenum < 0.04 THEN 'borderline'
      ELSE 'elevated'
    END AS troponin_category
  FROM first_troponin
  WHERE rn = 1
)
SELECT 
  troponin_category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 2) AS percentage,
  AVG(valuenum) AS mean,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY valuenum) AS median,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY valuenum) - 
  PERCENTILE_CONT(0.25) WITHIN GROUP (ORDER BY valuenum) AS iqr
FROM categorized
GROUP BY troponin_category;