WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 82 AND 92
),
temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(unitname) IN ('°c','celsius')
    AND LOWER(label) LIKE '%temperature%'   -- catches items named Temperature (C)
),
temps_first24 AS (
  SELECT
    c.stay_id,
    ce.charttime,
    ce.valuenum
  FROM cohort AS c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON c.stay_id = ce.stay_id
  JOIN temp_items AS di
    ON ce.itemid = di.itemid
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
),
avg_temp_per_stay AS (
  SELECT
    stay_id,
    AVG(valuenum) AS avg_temp
  FROM temps_first24
  GROUP BY stay_id
),
stats AS (
  SELECT
    COUNT(*) AS total_stays,
    COUNTIF(avg_temp <= 37.5) AS stays_le_value
  FROM avg_temp_per_stay
)
SELECT
  stays_le_value,
  total_stays,
  SAFE_DIVIDE(stays_le_value, total_stays) * 100 AS percentile_37_5
FROM stats;