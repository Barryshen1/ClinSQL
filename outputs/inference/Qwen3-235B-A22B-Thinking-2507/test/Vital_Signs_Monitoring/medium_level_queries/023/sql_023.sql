WITH population AS (
  SELECT 
    i.subject_id,
    i.hadm_id,
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 62 AND 72
),

-- Step 2: Get temperature measurements in the first 24 hours
temp_measurements AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    p.stay_id,
    c.valuenum,
    CASE 
      WHEN c.valuenum < 36.0 THEN '<36.0'
      WHEN c.valuenum >= 36.0 AND c.valuenum < 38.0 THEN '36.0-37.9'
      WHEN c.valuenum >= 38.0 THEN '>=38.0'
    END AS temp_category
  FROM population p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON p.stay_id = c.stay_id
  WHERE c.itemid = 223762  -- Temperature Celsius
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN p.intime AND DATETIME_ADD(p.intime, INTERVAL 24 HOUR)
),

-- Step 3: Define AKI codes
aki_codes AS (
  SELECT 'N170' AS icd_code, 10 AS icd_version UNION ALL
  SELECT 'N171', 10 UNION ALL
  SELECT 'N172', 10 UNION ALL
  SELECT 'N178', 10 UNION ALL
  SELECT 'N179', 10 UNION ALL
  SELECT '5840', 9 UNION ALL
  SELECT '5841', 9 UNION ALL
  SELECT '5842', 9 UNION ALL
  SELECT '5843', 9 UNION ALL
  SELECT '5844', 9 UNION ALL
  SELECT '5845', 9 UNION ALL
  SELECT '5846', 9 UNION ALL
  SELECT '5847', 9 UNION ALL
  SELECT '5848', 9 UNION ALL
  SELECT '5849', 9
),

-- Step 4: Get AKI flag for each admission
aki_flag AS (
  SELECT 
    d.hadm_id,
    1 AS aki_flag
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN aki_codes a
    ON d.icd_code = a.icd_code AND d.icd_version = a.icd_version
  GROUP BY d.hadm_id
),

-- Step 5: Calculate temperature statistics per category
temp_stats AS (
  SELECT 
    temp_category,
    AVG(valuenum) AS mean_temp,
    APPROX_QUANTILES(valuenum, 1000)[OFFSET(500)] AS median_temp,
    APPROX_QUANTILES(valuenum, 1000)[OFFSET(750)] - APPROX_QUANTILES(valuenum, 1000)[OFFSET(250)] AS iqr_temp
  FROM temp_measurements
  GROUP BY temp_category
),

-- Step 6: Determine which patients had measurements in each category
patient_category AS (
  SELECT 
    p.subject_id,
    p.hadm_id,
    MAX(CASE WHEN tm.temp_category = '<36.0' THEN 1 ELSE 0 END) AS has_low,
    MAX(CASE WHEN tm.temp_category = '36.0-37.9' THEN 1 ELSE 0 END) AS has_mid,
    MAX(CASE WHEN tm.temp_category = '>=38.0' THEN 1 ELSE 0 END) AS has_high
  FROM population p
  LEFT JOIN temp_measurements tm ON p.stay_id = tm.stay_id
  GROUP BY p.subject_id, p.hadm_id
),

-- Step 7: Calculate AKI rate per category
aki_rates AS (
  SELECT 
    '<36.0' AS temp_category,
    SAFE_DIVIDE(
      SUM(CASE WHEN pc.has_low = 1 AND COALESCE(a.aki_flag, 0) = 1 THEN 1 ELSE 0 END),
      COUNTIF(pc.has_low = 1)
    ) AS aki_rate
  FROM patient_category pc
  LEFT JOIN aki_flag a ON pc.hadm_id = a.hadm_id
  GROUP BY 1
  
  UNION ALL
  
  SELECT 
    '36.0-37.9',
    SAFE_DIVIDE(
      SUM(CASE WHEN pc.has_mid = 1 AND COALESCE(a.aki_flag, 0) = 1 THEN 1 ELSE 0 END),
      COUNTIF(pc.has_mid = 1)
    )
  FROM patient_category pc
  LEFT JOIN aki_flag a ON pc.hadm_id = a.hadm_id
  GROUP BY 1
  
  UNION ALL
  
  SELECT 
    '>=38.0',
    SAFE_DIVIDE(
      SUM(CASE WHEN pc.has_high = 1 AND COALESCE(a.aki_flag, 0) = 1 THEN 1 ELSE 0 END),
      COUNTIF(pc.has_high = 1)
    )
  FROM patient_category pc
  LEFT JOIN aki_flag a ON pc.hadm_id = a.hadm_id
  GROUP BY 1
)

-- Final result: Combine temperature stats with AKI rates
SELECT 
  ts.temp_category,
  ROUND(ts.mean_temp, 2) AS mean_temp,
  ROUND(ts.median_temp, 2) AS median_temp,
  ROUND(ts.iqr_temp, 2) AS iqr_temp,
  ROUND(ar.aki_rate, 4) AS aki_rate
FROM temp_stats ts
JOIN aki_rates ar ON ts.temp_category = ar.temp_category
ORDER BY 
  CASE ts.temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0-37.9' THEN 2
    WHEN '>=38.0' THEN 3
  END;