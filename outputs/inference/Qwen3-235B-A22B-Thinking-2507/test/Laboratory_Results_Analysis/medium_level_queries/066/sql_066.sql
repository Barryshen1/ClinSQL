WITH base_admissions AS (
  SELECT 
    a.hadm_id,
    COALESCE(a.edregtime, a.admittime) AS start_time
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'M'
    AND d.seq_num = 1
    AND d.icd_code IN ('R072', 'R073', 'R074', 'R078', 'R079')
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 39 AND 49
),
first_tnt AS (
  SELECT 
    l.hadm_id,
    l.valuenum,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime) as rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN base_admissions b
    ON l.hadm_id = b.hadm_id
  WHERE l.itemid = 50672
    AND l.charttime >= b.start_time
    AND l.valuenum IS NOT NULL
),
categorized AS (
  SELECT 
    hadm_id,
    valuenum,
    CASE 
      WHEN valuenum < 14 THEN 'normal'
      WHEN valuenum < 60 THEN 'borderline'
      ELSE 'myocardial_injury'
    END as category
  FROM first_tnt
  WHERE rn = 1
)
SELECT 
  category,
  COUNT(*) as count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) as percentage,
  ROUND(AVG(valuenum), 2) as mean,
  APPROX_QUANTILES(valuenum, 1000)[OFFSET(500)] as median,
  ROUND(APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)], 2) as iqr
FROM categorized
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'myocardial_injury' THEN 3
  END;