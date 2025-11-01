WITH qualifying_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'F'
    AND anchor_age >= 86
    AND anchor_age <= 96
),
temperature_readings AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN qualifying_patients qp
    ON ce.subject_id = qp.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.stay_id = icu.stay_id
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 1 DAY)
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.category = 'Temperature'
    AND ce.valueuom = 'F'
    AND ce.valuenum IS NOT NULL
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(75)] AS p75_temperature_f
FROM temperature_readings;