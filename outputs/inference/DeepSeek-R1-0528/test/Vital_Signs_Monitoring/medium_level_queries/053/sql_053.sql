WITH filtered_patients AS (
  SELECT 
    p.subject_id, 
    icu.stay_id,
    icu.intime,
    -- Calculate exact age at ICU admission
    p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_admission
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year)) BETWEEN 65 AND 75
),
sbp_events AS (
  SELECT 
    fp.stay_id,
    ce.valuenum AS sbp_value
  FROM filtered_patients fp
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fp.stay_id = ce.stay_id
  WHERE 
    ce.itemid IN (220050, 220179)  -- Systolic BP item IDs
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0            -- Exclude invalid values
    AND ce.charttime >= fp.intime
    AND ce.charttime <= DATETIME_ADD(fp.intime, INTERVAL 24 HOUR)
),
categorized_sbp AS (
  SELECT 
    sbp_value,
    CASE 
      WHEN sbp_value < 140 THEN '<140'
      WHEN sbp_value BETWEEN 140 AND 159 THEN '140-159'
      WHEN sbp_value >= 160 THEN '>=160'
    END AS sbp_category
  FROM sbp_events
),
stats AS (
  SELECT 
    sbp_category,
    COUNT(*) AS num_measurements,
    AVG(sbp_value) AS mean_sbp,
    APPROX_QUANTILES(sbp_value, 100) AS quantiles  -- 101-point quantile array
  FROM categorized_sbp
  GROUP BY sbp_category
)
SELECT 
  sbp_category,
  num_measurements,
  ROUND(mean_sbp, 2) AS mean_sbp,
  ROUND(quantiles[OFFSET(50)], 2) AS median_sbp,  -- 50th percentile
  ROUND(quantiles[OFFSET(75)] - quantiles[OFFSET(25)], 2) AS iqr  -- Q3 - Q1
FROM stats
ORDER BY 
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '>=160' THEN 3
  END;