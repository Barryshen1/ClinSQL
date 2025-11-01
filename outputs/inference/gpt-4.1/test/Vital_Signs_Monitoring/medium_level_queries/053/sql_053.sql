WITH sbp_items AS (
  -- Identify itemids for systolic blood pressure
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(label) LIKE '%blood pressure%'
),

female_icu_stays AS (
  -- Get female ICU stays age 65-75
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
),

sbp_measurements AS (
  -- Get SBP measurements in first 24h of ICU stay
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM physionet-data.mimiciv_3_1_icu.chartevents ce
  JOIN sbp_items si ON ce.itemid = si.itemid
  JOIN female_icu_stays fis
    ON ce.stay_id = fis.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN fis.intime AND TIMESTAMP_ADD(fis.intime, INTERVAL 24 HOUR)
)

SELECT
  CASE
    WHEN valuenum < 140 THEN '<140'
    WHEN valuenum >= 140 AND valuenum < 160 THEN '140–159'
    WHEN valuenum >= 160 THEN '≥160'
    ELSE 'Unknown'
  END AS sbp_category,
  COUNT(*) AS n_measurements,
  ROUND(AVG(valuenum), 2) AS mean_sbp,
  ROUND(APPROX_QUANTILES(valuenum, 2)[OFFSET(1)], 2) AS median_sbp,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(1)], 2) AS iqr_25,
  ROUND(APPROX_QUANTILES(valuenum, 4)[OFFSET(3)], 2) AS iqr_75
FROM sbp_measurements
WHERE valuenum IS NOT NULL
GROUP BY sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140–159' THEN 2
    WHEN '≥160' THEN 3
    ELSE 4
  END;