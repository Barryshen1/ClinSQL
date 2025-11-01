WITH cohort AS (
  SELECT 
    p.subject_id, 
    p.gender,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    -- Calculate age using MIMIC-IV's method: anchor_age + (admission year - anchor_year)
    p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 62 AND 72
),

aki_patients AS (
  SELECT 
    hadm_id,
    1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE 
    (icd_version = 9 AND icd_code LIKE '584%') OR
    (icd_version = 10 AND icd_code LIKE 'N17%')
),

cohort_with_aki AS (
  SELECT 
    c.*,
    COALESCE(aki.aki_flag, 0) AS aki_flag
  FROM cohort c
  LEFT JOIN aki_patients aki
    ON c.hadm_id = aki.hadm_id
),

temp_measurements AS (
  SELECT 
    c.stay_id,
    c.subject_id,
    c.hadm_id,
    c.aki_flag,
    ce.charttime,
    ce.itemid,
    -- Convert Fahrenheit to Celsius, use Celsius values directly
    CASE 
      WHEN ce.itemid = 223761 THEN (ce.valuenum - 32) * 5/9
      ELSE ce.valuenum
    END AS temp_c
  FROM cohort_with_aki c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (223762, 223761, 220734)  -- Temperature items
    AND ce.valuenum IS NOT NULL
    -- Use TIMESTAMP_ADD for timestamp columns
    AND ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 24 HOUR)
),

temp_with_categories AS (
  SELECT 
    *,
    CASE 
      WHEN temp_c < 36.0 THEN '<36.0'
      WHEN temp_c >= 36.0 AND temp_c < 38.0 THEN '36.0–37.9'
      WHEN temp_c >= 38.0 THEN '≥38.0'
      ELSE NULL 
    END AS temp_category
  FROM temp_measurements
  WHERE temp_c IS NOT NULL
),

temp_agg AS (
  SELECT 
    temp_category,
    AVG(temp_c) AS mean_temp,
    APPROX_QUANTILES(temp_c, 100) AS quantiles,  -- Array of 101 quantiles (0-100)
    COUNT(DISTINCT CASE WHEN aki_flag = 1 THEN subject_id END) AS aki_patients_count,
    COUNT(DISTINCT subject_id) AS total_patients_count
  FROM temp_with_categories
  WHERE temp_category IS NOT NULL
  GROUP BY temp_category
)

SELECT 
  temp_category,
  mean_temp,
  quantiles[OFFSET(50)] AS median_temp,  -- 50th percentile
  quantiles[OFFSET(25)] AS q1_temp,      -- 25th percentile
  quantiles[OFFSET(75)] AS q3_temp,      -- 75th percentile
  quantiles[OFFSET(75)] - quantiles[OFFSET(25)] AS iqr_temp,  -- IQR = Q3 - Q1
  aki_patients_count,
  total_patients_count,
  SAFE_DIVIDE(aki_patients_count, total_patients_count) AS aki_rate
FROM temp_agg
ORDER BY 
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
  END;