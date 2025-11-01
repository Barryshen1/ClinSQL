WITH systolic_items AS (
  -- identify itemids that represent systolic BP measurements
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
),

cohort_icustays AS (
  -- female patients age 65-75 (inclusive) and their ICU stays
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),

measurements AS (
  -- systolic BP measurements in the first 24 hours of the ICU stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.itemid,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN systolic_items si
    ON ce.itemid = si.itemid
  JOIN cohort_icustays icu
    ON ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    -- restrict to the first 24 hours of the ICU stay
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    -- plausible physiologic filter to reduce obvious data entry errors
    AND ce.valuenum > 20
    AND ce.valuenum < 300
),

categorized AS (
  SELECT
    CASE
      WHEN valuenum < 140 THEN '<140'
      WHEN valuenum BETWEEN 140 AND 159 THEN '140-159'
      ELSE '>=160'
    END AS sbp_category,
    valuenum
  FROM measurements
)

-- Final summary per category: count, mean, median, IQR (Q3 - Q1)
SELECT
  sbp_category AS category,
  cnt AS n_measurements,
  ROUND(mean_sbp, 2) AS mean_sbp,
  quantiles[OFFSET(2)] AS median_sbp,
  quantiles[OFFSET(3)] - quantiles[OFFSET(1)] AS iqr_sbp,
  quantiles[OFFSET(1)] AS q1_sbp,
  quantiles[OFFSET(3)] AS q3_sbp
FROM (
  SELECT
    sbp_category,
    COUNT(*) AS cnt,
    AVG(valuenum) AS mean_sbp,
    APPROX_QUANTILES(valuenum, 4) AS quantiles
  FROM categorized
  GROUP BY sbp_category
)
ORDER BY
  CASE sbp_category WHEN '<140' THEN 1 WHEN '140-159' THEN 2 ELSE 3 END;