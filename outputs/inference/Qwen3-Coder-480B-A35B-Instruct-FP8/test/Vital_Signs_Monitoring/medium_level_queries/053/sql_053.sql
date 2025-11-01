WITH sbp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%systolic%'
    AND LOWER(category) LIKE '%blood pressure%'
),

sbp_measurements AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.valuenum AS sbp_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN sbp_itemids si ON ce.itemid = si.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON ce.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 65 AND 75
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= icu.intime
    AND ce.charttime <= DATETIME_ADD(icu.intime, INTERVAL 24 HOUR)
)

SELECT
  CASE
    WHEN sbp_value < 140 THEN '<140'
    WHEN sbp_value BETWEEN 140 AND 159 THEN '140–159'
    WHEN sbp_value >= 160 THEN '≥160'
  END AS sbp_category,
  AVG(sbp_value) AS mean_sbp,
  APPROX_QUANTILES(sbp_value, 2)[OFFSET(1)] AS median_sbp,
  APPROX_QUANTILES(sbp_value, 4)[OFFSET(1)] AS q1_sbp,
  APPROX_QUANTILES(sbp_value, 4)[OFFSET(3)] AS q3_sbp,
  APPROX_QUANTILES(sbp_value, 4)[OFFSET(3)] - APPROX_QUANTILES(sbp_value, 4)[OFFSET(1)] AS iqr_sbp
FROM sbp_measurements
GROUP BY sbp_category
ORDER BY
  CASE sbp_category
    WHEN '<140' THEN 1
    WHEN '140–159' THEN 2
    WHEN '≥160' THEN 3
  END;