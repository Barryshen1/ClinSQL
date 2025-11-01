WITH RelevantStays AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON s.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 67 AND 77
), TemperatureMeasurements AS (
  SELECT
    s.stay_id,
    ce.charttime,
    ce.valuenum AS temperature
  FROM RelevantStays AS s
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON s.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220187 -- Temperature (Celsius)
    AND ce.charttime BETWEEN s.intime AND s.intime + INTERVAL '24' HOUR
), AverageTemperatures AS (
  SELECT
    stay_id,
    AVG(temperature) AS avg_temperature
  FROM TemperatureMeasurements
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(avg_temperature, 0.5) AS median_avg_temperature
FROM AverageTemperatures;