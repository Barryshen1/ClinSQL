WITH hr_data AS (
  SELECT
    ce.valuenum AS heart_rate
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON ce.stay_id = ie.stay_id AND ce.subject_id = ie.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
    AND ce.itemid = 220045  -- Heart rate
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.valuenum < 300   -- Reasonable range
    AND ce.charttime >= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)  -- ICU day 2+
)
SELECT
  APPROX_QUANTILES(heart_rate, 100)[OFFSET(25)] AS q1,
  APPROX_QUANTILES(heart_rate, 100)[OFFSET(75)] AS q3,
  APPROX_QUANTILES(heart_rate, 100)[OFFSET(75)] - APPROX_QUANTILES(heart_rate, 100)[OFFSET(25)] AS iqr
FROM hr_data;