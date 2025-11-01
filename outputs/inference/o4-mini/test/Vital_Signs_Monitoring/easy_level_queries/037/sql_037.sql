WITH eligible_stays AS (
  SELECT
    icustays.subject_id,
    icustays.hadm_id,
    icustays.stay_id,
    icustays.intime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` AS icustays
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` AS patients
  USING(subject_id)
  WHERE
    patients.gender = 'F'
    AND patients.anchor_age BETWEEN 89 AND 99
),
map_items AS (
  SELECT
    itemid
  FROM
    `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE
    LOWER(label) LIKE '%mean arterial pressure%'
)
SELECT
  AVG(c.valuenum) AS average_map_first_24h
FROM
  eligible_stays AS s
JOIN
  `physionet-data.mimiciv_3_1_icu.chartevents` AS c
  ON s.stay_id = c.stay_id
JOIN
  map_items AS mi
  ON c.itemid = mi.itemid
WHERE
  c.valuenum IS NOT NULL
  AND c.charttime BETWEEN s.intime
    AND TIMESTAMP_ADD(s.intime, INTERVAL 24 HOUR);