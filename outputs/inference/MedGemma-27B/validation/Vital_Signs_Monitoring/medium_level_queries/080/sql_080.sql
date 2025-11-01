WITH PatientInfo AS (
  SELECT
    subject_id,
    gender,
    anchor_age
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE
    gender = 'F' AND anchor_age BETWEEN 56 AND 66
),
ICUStays AS (
  SELECT
    s.stay_id,
    s.subject_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    PatientInfo AS p
    ON s.subject_id = p.subject_id
),
MAPValues AS (
  SELECT
    s.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON s.stay_id = ce.stay_id
  WHERE
    ce.itemid = 455
    AND ce.charttime BETWEEN s.intime AND TIMESTAMP_ADD(s.intime, INTERVAL 48 HOUR)
)
SELECT
  CASE
    WHEN AVG(map_value) < 65
    THEN '<65'
    WHEN AVG(map_value) BETWEEN 65 AND 74
    THEN '65-74'
    WHEN AVG(map_value) BETWEEN 75 AND 84
    THEN '75-84'
    ELSE '>=85'
  END AS map_category,
  COUNT(stay_id) AS count,
  AVG(map_value) AS mean,
  MEDIAN(map_value) AS median,
  PERCENTILE_CONT(map_value, 0.25) AS iqr_25,
  PERCENTILE_CONT(map_value, 0.75) AS iqr_75
FROM
  MAPValues
GROUP BY
  map_category;