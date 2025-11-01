WITH cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 41 AND 51
    AND d.seq_num = 1
    AND (
      (d.icd_version = 9 AND (d.icd_code LIKE '410.%' OR d.icd_code LIKE '786.5%'))
      OR
      (d.icd_version = 10 AND (d.icd_code LIKE 'I21%' OR d.icd_code LIKE 'R07%'))
    )
),
troponins AS (
  SELECT 
    le.hadm_id,
    le.charttime,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime ASC) AS rn
  FROM 
    `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN 
    cohort c
    ON le.hadm_id = c.hadm_id
  WHERE 
    le.itemid = 50586
    AND le.valuenum IS NOT NULL
    AND le.charttime >= c.admittime
),
initial_troponin AS (
  SELECT 
    hadm_id,
    valuenum
  FROM 
    troponins
  WHERE 
    rn = 1
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 1) AS percentage,
  ROUND(AVG(valuenum), 4) AS mean,
  APPROX_QUANTILES(valuenum, 2)[OFFSET(1)] AS median,
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] - APPROX_QUANTILES(valuenum, 4)[OFFSET(1)] AS IQR
FROM (
  SELECT 
    valuenum,
    CASE 
      WHEN valuenum <= 0.01 THEN 'normal'
      WHEN valuenum > 0.01 AND valuenum <= 0.1 THEN 'borderline'
      ELSE 'elevated'
    END AS category
  FROM 
    initial_troponin
)
GROUP BY 
  category
ORDER BY 
  CASE category 
    WHEN 'normal' THEN 1 
    WHEN 'borderline' THEN 2 
    ELSE 3 
  END;