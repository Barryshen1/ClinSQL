WITH female_icu_stays AS (
  -- Get female patients aged 65-75 with ICU stays
  SELECT
    s.subject_id,
    s.hadm_id,
    s.stay_id,
    s.intime,
    s.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` s
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    s.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 65 AND 75
),

systolic_bp_measurements AS (
  -- Get systolic BP measurements in first 24 hours of ICU stay
  SELECT
    f.subject_id,
    f.stay_id,
    ce.valuenum AS systolic_bp,
    TIMESTAMP_DIFF(ce.charttime, f.intime, HOUR) AS hours_since_admission
  FROM
    female_icu_stays f
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    f.stay_id = ce.stay_id
  JOIN
    `physionet-data.mimiciv_3_1_icu.d_items` di
  ON
    ce.itemid = di.itemid
  WHERE
    di.label = 'Systolic Blood Pressure'
    AND ce.valuenum IS NOT NULL
    AND TIMESTAMP_DIFF(ce.charttime, f.intime, HOUR) <= 24
)

SELECT
  CASE
    WHEN systolic_bp < 140 THEN '<140'
    WHEN systolic_bp BETWEEN 140 AND 159 THEN '140-159'
    WHEN systolic_bp >= 160 THEN '>=160'
  END AS bp_category,
  COUNT(*) AS measurement_count,
  ROUND(AVG(systolic_bp), 2) AS mean_bp,
  ROUND(APPROX_QUANTILES(systolic_bp, 100)[OFFSET(50)], 2) AS median_bp,
  ROUND(APPROX_QUANTILES(systolic_bp, 100)[OFFSET(25)], 2) AS q1_bp,
  ROUND(APPROX_QUANTILES(systolic_bp, 100)[OFFSET(75)], 2) AS q3_bp,
  ROUND(APPROX_QUANTILES(systolic_bp, 100)[OFFSET(75)] - APPROX_QUANTILES(systolic_bp, 100)[OFFSET(25)], 2) AS iqr
FROM
  systolic_bp_measurements
GROUP BY
  bp_category
ORDER BY
  CASE bp_category
    WHEN '<140' THEN 1
    WHEN '140-159' THEN 2
    WHEN '>=160' THEN 3
  END;