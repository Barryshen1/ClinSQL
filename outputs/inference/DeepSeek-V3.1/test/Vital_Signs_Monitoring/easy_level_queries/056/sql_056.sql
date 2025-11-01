WITH temp_measurements AS (
  SELECT
    ce.valuenum AS temp_f
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON ce.stay_id = ie.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 46 AND 56
    AND ce.itemid IN (223761, 223762)  -- Temperature Fahrenheit
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0  -- reasonable lower bound
    AND ce.valuenum < 120 -- reasonable upper bound
    AND ce.charttime >= ie.intime
    AND ce.charttime <= DATETIME_ADD(ie.intime, INTERVAL 24 HOUR)
)
SELECT
  APPROX_QUANTILES(temp_f, 2)[OFFSET(1)] AS median_temp_f
FROM temp_measurements;