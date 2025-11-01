WITH temp_items AS (
  -- Identify itemids for temperature measurements
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%temp%'
    AND param_type = 'Numeric'
),
female_aged_89_99 AS (
  -- Get female ICU patients aged 89-99
  SELECT DISTINCT icu.subject_id, icu.hadm_id, icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 89 AND 99
),
temp_measurements AS (
  -- Get temperature measurements for these patients
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN temp_items ti ON ce.itemid = ti.itemid
  JOIN female_aged_89_99 fa ON ce.subject_id = fa.subject_id AND ce.stay_id = fa.stay_id
  WHERE ce.valuenum IS NULL OR (ce.valuenum >= 25 AND ce.valuenum <= 45) -- plausible temps in °C
),
categorized_temps AS (
  -- Categorize each measurement
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    charttime,
    valuenum,
    CASE
      WHEN valuenum IS NULL THEN 'Missing'
      WHEN valuenum < 36 THEN '<36'
      WHEN valuenum >= 36 AND valuenum < 38 THEN '36–37.9'
      WHEN valuenum >= 38 THEN '≥38'
      ELSE 'Other'
    END AS temp_category
  FROM temp_measurements
)
SELECT
  temp_category,
  COUNT(*) AS measurement_count,
  COUNT(DISTINCT subject_id) AS unique_patient_count,
  ROUND(AVG(valuenum), 2) AS mean_temp,
  ROUND(APPROX_QUANTILES(valuenum, 2)[OFFSET(1)], 2) AS median_temp,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 2) AS temp_25th_percentile,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 2) AS temp_75th_percentile,
  ROUND(
    SAFE_DIVIDE(
      SUM(CASE WHEN valuenum IS NULL THEN 1 ELSE 0 END),
      COUNT(*)
    ), 4
  ) AS mi_rate
FROM categorized_temps
WHERE temp_category IN ('<36', '36–37.9', '≥38', 'Missing')
GROUP BY temp_category
ORDER BY
  CASE temp_category
    WHEN '<36' THEN 1
    WHEN '36–37.9' THEN 2
    WHEN '≥38' THEN 3
    WHEN 'Missing' THEN 4
    ELSE 5
  END;