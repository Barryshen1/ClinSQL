WITH chest_pain_cohort AS (
  SELECT 
    a.hadm_id,
    p.subject_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id AND d.seq_num = 1
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 87 AND 97
    AND (
      (d.icd_version = 9 AND d.icd_code IN ('78650', '78651', '78659'))
      OR
      (d.icd_version = 10 AND d.icd_code IN ('R07.2', 'R07.4', 'R07.89', 'R07.9'))
    )
),

first_troponin AS (
  SELECT 
    le.hadm_id,
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN chest_pain_cohort cpc
    ON le.hadm_id = cpc.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON le.hadm_id = a.hadm_id
  WHERE le.itemid IN (50672, 50673)
    AND le.valuenum IS NOT NULL
    AND le.charttime >= COALESCE(a.edregtime, a.admittime)
    AND le.charttime <= a.dischtime
),

categorized AS (
  SELECT 
    CASE 
      WHEN ft.valuenum <= 0.04 THEN 'Normal'
      WHEN ft.valuenum > 0.04 AND ft.valuenum <= 0.1 THEN 'Borderline'
      WHEN ft.valuenum > 0.1 THEN 'Injury'
    END AS category,
    ft.valuenum
  FROM first_troponin ft
  WHERE ft.rn = 1
),

grouped AS (
  SELECT 
    category,
    COUNT(*) AS count_cat,
    AVG(valuenum) AS mean_val,
    APPROX_QUANTILES(valuenum, 100) AS quantiles
  FROM categorized
  GROUP BY category
)

SELECT 
  category,
  count_cat,
  count_cat * 100.0 / SUM(count_cat) OVER () AS percentage,
  mean_val,
  quantiles[OFFSET(50)] AS median_val,
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_val
FROM grouped
ORDER BY 
  CASE category 
    WHEN 'Normal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Injury' THEN 3
  END;