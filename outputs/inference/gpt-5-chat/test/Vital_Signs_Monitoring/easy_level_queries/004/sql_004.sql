WITH cohort AS (
  SELECT icu.subject_id,
         icu.hadm_id,
         icu.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 37 AND 47
),
temp_events AS (
  SELECT ce.stay_id,
         ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON ce.itemid = di.itemid
  JOIN cohort AS c
    ON ce.stay_id = c.stay_id
  WHERE di.label LIKE '%Temperature%'
    AND ce.valuenum IS NOT NULL
),
mean_temp_per_stay AS (
  SELECT stay_id,
         AVG(valuenum) AS mean_temperature
  FROM temp_events
  GROUP BY stay_id
)
SELECT
  APPROX_QUANTILES(mean_temperature, 100)[OFFSET(75)] AS percentile_75_mean_temp
FROM mean_temp_per_stay;