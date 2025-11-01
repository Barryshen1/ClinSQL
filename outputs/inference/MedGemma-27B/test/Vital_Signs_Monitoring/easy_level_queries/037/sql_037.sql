WITH RelevantPatients AS (
  SELECT
    p.subject_id
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
  WHERE
    p.gender = 'F' AND p.anchor_age >= 89 AND p.anchor_age <= 99
), ICUStays AS (
  SELECT
    s.subject_id,
    s.stay_id,
    s.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS s
  WHERE
    s.subject_id IN (SELECT subject_id FROM RelevantPatients)
), MAPMeasurements AS (
  SELECT
    ic.subject_id,
    ic.stay_id,
    ic.intime,
    ce.charttime,
    ce.valuenum AS map_value
  FROM
    ICUStays AS ic
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ic.subject_id = ce.subject_id AND ic.stay_id = ce.stay_id
  WHERE
    ce.itemid = 455 -- MAP itemid
    AND ce.valuenum IS NOT NULL
)
SELECT
  AVG(map_value) AS average_map
FROM
  MAPMeasurements
WHERE
  charttime BETWEEN intime AND DATETIME_ADD(intime, INTERVAL 24 HOUR);