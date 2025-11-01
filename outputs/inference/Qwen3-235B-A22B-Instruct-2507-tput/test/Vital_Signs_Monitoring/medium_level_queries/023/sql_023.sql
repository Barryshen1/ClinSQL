WITH cohort AS (
  SELECT p.subject_id, i.hadm_id, i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_hosp`.patients p
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.icustays i
    ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND (EXTRACT(YEAR FROM i.intime) - p.anchor_year + p.anchor_age) BETWEEN 62 AND 72
),
temp_items AS (
  SELECT itemid 
  FROM `physionet-data.mimiciv_3_1_icu`.d_items 
  WHERE LOWER(label) LIKE '%temperature%'
),
aki_codes AS (
  SELECT icd_code 
  FROM `physionet-data.mimiciv_3_1_hosp`.d_icd_diagnoses 
  WHERE LOWER(long_title) LIKE '%acute kidney injury%'
),
aki_patients AS (
  SELECT DISTINCT di.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp`.diagnoses_icd di
  INNER JOIN aki_codes ac ON di.icd_code = ac.icd_code AND di.icd_version = 10
),
temps AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.valuenum AS temp_value,
    CASE 
      WHEN ce.valuenum < 36.0 THEN '<36.0'
      WHEN ce.valuenum >= 36.0 AND ce.valuenum <= 37.9 THEN '36.0-37.9'
      WHEN ce.valuenum >= 38.0 THEN '>=38.0'
      ELSE NULL 
    END AS temp_category
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu`.chartevents ce
    ON c.stay_id = ce.stay_id
  CROSS JOIN temp_items ti
  WHERE ce.itemid = ti.itemid
    AND ce.charttime >= c.intime 
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum BETWEEN 30 AND 45  -- reasonable body temp range
),
temp_stats AS (
  SELECT 
    temp_category,
    AVG(temp_value) AS mean_temperature,
    APPROX_QUANTILES(temp_value, 1000)[OFFSET(500)] AS median_temperature,
    APPROX_QUANTILES(temp_value, 1000)[OFFSET(750)] - APPROX_QUANTILES(temp_value, 1000)[OFFSET(250)] AS iqr_temperature,
    COUNT(*) AS measurement_count
  FROM temps
  GROUP BY temp_category
),
patient_category AS (
  SELECT DISTINCT subject_id, temp_category
  FROM temps
),
aki_rate AS (
  SELECT 
    pc.temp_category,
    COUNT(*) AS patient_count,
    COUNT(ak.subject_id) AS aki_count,
    ROUND(COUNT(ak.subject_id) * 1.0 / COUNT(*), 3) AS aki_rate
  FROM patient_category pc
  LEFT JOIN aki_patients ak ON pc.subject_id = ak.subject_id
  GROUP BY pc.temp_category
)
SELECT 
  ts.temp_category,
  ts.mean_temperature,
  ts.median_temperature,
  ts.iqr_temperature,
  ar.aki_rate
FROM temp_stats ts
INNER JOIN aki_rate ar ON ts.temp_category = ar.temp_category
ORDER BY ts.temp_category;