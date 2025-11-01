WITH age_adm AS (
  SELECT 
    p.subject_id,
    a.hadm_id,
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age_at_admission,
    a.admittime,
    a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 79 AND 89
),
acs_adm AS (
  SELECT DISTINCT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 10 AND (icd_code LIKE 'I20%' OR icd_code LIKE 'I21%'))
    OR (icd_version = 9 AND (icd_code LIKE '410%' OR icd_code LIKE '411%'))
),
filtered_adm AS (
  SELECT aa.*
  FROM age_adm aa
  INNER JOIN acs_adm acs ON aa.hadm_id = acs.hadm_id
),
troponin AS (
  SELECT 
    fa.hadm_id,
    le.charttime,  -- Added to preserve temporal ordering
    le.valuenum,
    CASE 
      WHEN le.valuenum < 14 THEN 'normal'
      WHEN le.valuenum BETWEEN 14 AND 29 THEN 'borderline'
      WHEN le.valuenum >= 30 THEN 'elevated'
    END AS category
  FROM filtered_adm fa
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON fa.hadm_id = le.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dli
    ON le.itemid = dli.itemid
  WHERE 
    LOWER(dli.label) LIKE '%troponin t%'
    AND le.valueuom = 'ng/L'
    AND le.valuenum IS NOT NULL
    AND le.charttime BETWEEN fa.admittime AND fa.dischtime
),
first_troponin AS (
  SELECT 
    hadm_id,
    valuenum,
    category,
    ROW_NUMBER() OVER (
      PARTITION BY hadm_id 
      ORDER BY charttime
    ) AS rn
  FROM troponin
)
SELECT 
  category,
  COUNT(*) AS count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentage,
  ROUND(AVG(valuenum), 2) AS mean,
  APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median,
  ROUND(
    APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] - 
    APPROX_QUANTILES(valuenum, 100)[OFFSET(25)], 
    2
  ) AS iqr
FROM first_troponin
WHERE rn = 1 AND category IS NOT NULL
GROUP BY category
ORDER BY 
  CASE category
    WHEN 'normal' THEN 1
    WHEN 'borderline' THEN 2
    WHEN 'elevated' THEN 3
  END;