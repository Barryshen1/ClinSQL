WITH relevant_patients AS (
  SELECT
    subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'M' AND anchor_age BETWEEN 74 AND 84
),
temperature_data AS (
  SELECT
    ic.stay_id,
    ce.charttime,
    ce.valuenum AS temperature_f
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
    JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce ON ic.stay_id = ce.stay_id
    JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di ON ce.itemid = di.itemid
  WHERE
    ic.subject_id IN (SELECT subject_id FROM relevant_patients)
    AND di.label = 'Temperature'
    AND di.unitname = 'F'
),
min_temps AS (
  SELECT
    stay_id,
    MIN(temperature_f) AS min_temperature_f
  FROM
    temperature_data
  GROUP BY
    stay_id
)
SELECT
  stay_id,
  PERCENTILE_CONT(min_temperature_f, 0.5) AS median_min_temperature_f
FROM
  min_temps
GROUP BY
  stay_id
ORDER BY
  stay_id;