WITH PatientAge AS (
  SELECT
    subject_id,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 37 AND 47
),
FilteredStays AS (
  SELECT
    ic.stay_id,
    ic.subject_id
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS ic
  JOIN
    PatientAge AS pa
    ON ic.subject_id = pa.subject_id
),
Temperatures AS (
  SELECT
    fs.stay_id,
    ce.charttime,
    ce.valuenum AS temperature
  FROM
    FilteredStays AS fs
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON fs.stay_id = ce.stay_id
  WHERE
    ce.itemid = 220177 -- Temperature Celsius
),
MeanTemperatures AS (
  SELECT
    stay_id,
    AVG(temperature) AS mean_temperature
  FROM
    Temperatures
  GROUP BY
    stay_id
)
SELECT
  PERCENTILE_CONT(
    mean_temperature,
    0.75
  ) AS percentile_75
FROM
  MeanTemperatures;