WITH temp_itemids AS (
  -- Get itemids for temperature in Celsius
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temperature%' AND (LOWER(label) LIKE '%c%' OR LOWER(unitname) LIKE '%c%')
),

cohort AS (
  -- Female ICU patients aged 81–91
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 81 AND 91
),

temps_24h AS (
  -- Temperature measurements in first 24h of ICU stay
  SELECT
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  JOIN temp_itemids ti
    ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),

per_stay_temp AS (
  -- Per-stay mean temperature in first 24h
  SELECT
    c.stay_id,
    AVG(t.valuenum) AS mean_temp
  FROM cohort c
  LEFT JOIN temps_24h t
    ON c.stay_id = t.stay_id
  GROUP BY c.stay_id
),

classified AS (
  -- Classify per-stay mean temperature
  SELECT
    stay_id,
    mean_temp,
    CASE
      WHEN mean_temp IS NULL THEN 'Missing'
      WHEN mean_temp < 36.0 THEN '<36.0'
      WHEN mean_temp >= 36.0 AND mean_temp < 38.0 THEN '36.0–37.9'
      WHEN mean_temp >= 38.0 THEN '≥38.0'
      ELSE 'Other'
    END AS temp_category
  FROM per_stay_temp
)

SELECT
  temp_category,
  COUNTIF(temp_category != 'Missing') AS N,
  ROUND(AVG(mean_temp), 2) AS mean,
  ROUND(APPROX_QUANTILES(mean_temp, 2)[OFFSET(1)], 2) AS median,
  ROUND(APPROX_QUANTILES(mean_temp, 4)[OFFSET(1)], 2) AS iqr_25,
  ROUND(APPROX_QUANTILES(mean_temp, 4)[OFFSET(3)], 2) AS iqr_75,
  ROUND(100.0 * COUNTIF(temp_category = 'Missing') / COUNT(*), 2) AS mi_rate_percent
FROM classified
WHERE temp_category != 'Other'
GROUP BY temp_category
ORDER BY
  CASE temp_category
    WHEN '<36.0' THEN 1
    WHEN '36.0–37.9' THEN 2
    WHEN '≥38.0' THEN 3
    WHEN 'Missing' THEN 4
    ELSE 5
  END;