WITH temp_items AS (
  -- Identify ICU chart itemids that correspond to temperature measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperat%'
     OR LOWER(label) LIKE '%temp%'
     OR LOWER(abbreviation) LIKE '%temp%'
),

cohort_stays AS (
  -- Female patients aged 81-91 (anchor_age) and their ICU stays
  SELECT i.subject_id, i.hadm_id, i.stay_id, i.intime, i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    USING(subject_id)
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
),

temp_measurements AS (
  -- Temperature measurements within the first 24 hours of each ICU stay
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    ce.charttime,
    ce.valuenum,
    ce.valueuom,
    -- Convert Fahrenheit to Celsius if unit indicates Fahrenheit; otherwise assume Celsius
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN UPPER(COALESCE(ce.valueuom, '')) LIKE '%F%' THEN (ce.valuenum - 32.0) * 5.0/9.0
      ELSE ce.valuenum
    END AS temp_c
  FROM cohort_stays cs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = cs.stay_id
   AND ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
  WHERE ce.itemid IN (SELECT itemid FROM temp_items)
    AND ce.valuenum IS NOT NULL
    -- Keep only plausible temperature values in Celsius to reduce artifacts
    AND CASE
          WHEN UPPER(COALESCE(ce.valueuom, '')) LIKE '%F%' THEN (ce.valuenum - 32.0) * 5.0/9.0
          ELSE ce.valuenum
        END BETWEEN 25.0 AND 45.0
),

per_stay_mean AS (
  -- Compute per-stay mean temperature in the first 24 hours (may be NULL if no measurements)
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    AVG(tm.temp_c) AS mean_temp_c
  FROM cohort_stays cs
  LEFT JOIN temp_measurements tm
    USING(subject_id, hadm_id, stay_id)
  GROUP BY cs.subject_id, cs.hadm_id, cs.stay_id
),

stays_with_stats AS (
  -- Attach category labels and prepare for aggregation
  SELECT
    ps.*,
    CASE
      WHEN ps.mean_temp_c IS NULL THEN 'Missing'
      WHEN ps.mean_temp_c < 36.0 THEN '<36.0'
      WHEN ps.mean_temp_c >= 38.0 THEN '>=38.0'
      ELSE '36.0-37.9'
    END AS temp_category
  FROM per_stay_mean ps
),

cohort_counts AS (
  SELECT
    COUNT(*) AS total_stays,
    SUM(CASE WHEN mean_temp_c IS NULL THEN 1 ELSE 0 END) AS missing_stays
  FROM stays_with_stats
)

SELECT
  s.temp_category AS category,
  COUNT(*) AS n_stays,
  -- Mean of per-stay mean temperatures (NULL for category 'Missing')
  ROUND(AVG(s.mean_temp_c), 3) AS mean_of_means_c,
  -- Approximate median and IQR using APPROX_QUANTILES (returns NULL when no non-NULL values)
  (ARRAY_TO_STRING([SAFE_CAST( (APPROX_QUANTILES(s.mean_temp_c, 100))[OFFSET(50)] AS STRING)], '') ) AS median_of_means_c,
  -- IQR = Q3 - Q1
  ( 
    CASE
      WHEN (APPROX_QUANTILES(s.mean_temp_c, 100))[OFFSET(75)] IS NULL THEN NULL
      WHEN (APPROX_QUANTILES(s.mean_temp_c, 100))[OFFSET(25)] IS NULL THEN NULL
      ELSE ROUND((APPROX_QUANTILES(s.mean_temp_c, 100))[OFFSET(75)] - (APPROX_QUANTILES(s.mean_temp_c, 100))[OFFSET(25)], 3)
    END
  ) AS iqr_of_means_c,
  -- Overall missingness rate in the cohort (percent of stays with no temperature in first 24h)
  ROUND(100.0 * cc.missing_stays / cc.total_stays, 2) AS overall_mi_rate_pct
FROM stays_with_stats s
CROSS JOIN cohort_counts cc
GROUP BY s.temp_category, cc.total_stays, cc.missing_stays
ORDER BY
  -- Put categories in a sensible order
  CASE s.temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0-37.9' THEN 2
    WHEN '>=38.0' THEN 3
    WHEN 'Missing' THEN 4
    ELSE 5
  END;