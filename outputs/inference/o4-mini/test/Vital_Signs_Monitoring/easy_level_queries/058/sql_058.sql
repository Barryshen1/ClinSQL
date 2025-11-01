WITH temp_events AS (
  -- For each ICU stay of male patients aged 74-84, get all temperature measurements in °F
  SELECT
    icu.stay_id,
    ce.valuenum AS temp_f
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON p.subject_id = icu.subject_id
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
      ON icu.subject_id = ce.subject_id
      AND icu.hadm_id    = ce.hadm_id
      AND icu.stay_id    = ce.stay_id
      AND ce.charttime BETWEEN icu.intime AND icu.outtime
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 74 AND 84
    AND ce.valueuom = 'F'
    AND ce.valuenum IS NOT NULL
),
min_temps AS (
  -- Compute each stay's minimum temperature
  SELECT
    stay_id,
    MIN(temp_f) AS min_temp
  FROM
    temp_events
  GROUP BY
    stay_id
)
-- Compute the median of the per-stay minima
SELECT
  APPROX_QUANTILES(min_temp, 2)[OFFSET(1)] AS median_min_temperature_f
FROM
  min_temps;