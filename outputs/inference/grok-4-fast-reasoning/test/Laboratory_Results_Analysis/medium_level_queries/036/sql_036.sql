WITH tnt_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%' AND LOWER(label) LIKE '%high%'
),
qualifying_admissions AS (
  SELECT DISTINCT 
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di 
    ON a.hadm_id = di.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year BETWEEN 77 AND 87
    AND di.seq_num = 1
    AND (
      (di.icd_version = '10' AND di.icd_code LIKE 'I21%') 
      OR 
      (di.icd_version = '9' AND di.icd_code LIKE '410%')
    )
),
initial_tnt AS (
  SELECT 
    qa.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY qa.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM qualifying_admissions qa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON qa.hadm_id = le.hadm_id 
    AND le.charttime >= qa.admittime
  INNER JOIN tnt_items ti 
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
)
SELECT 
  hs_tnt_category,
  count,
  ROUND(count * 100.0 / SUM(count) OVER (), 2) AS percentage
FROM (
  SELECT 
    CASE 
      WHEN valuenum <= 0.014 THEN 'normal'
      WHEN valuenum > 0.014 AND valuenum <= 0.052 THEN 'borderline'
      ELSE 'myocardial injury'
    END AS hs_tnt_category,
    COUNT(*) AS count
  FROM initial_tnt
  WHERE rn = 1
  GROUP BY hs_tnt_category
)
ORDER BY 
  CASE hs_tnt_category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'myocardial injury' THEN 3
  END;