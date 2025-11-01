WITH female_elderly_icu AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    ie.stay_id,
    ie.intime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` ie
    ON p.subject_id = ie.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 89 AND 99
),
map_events AS (
  SELECT
    fe.subject_id,
    fe.stay_id,
    ce.charttime,
    ce.valuenum
  FROM female_elderly_icu fe
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fe.stay_id = ce.stay_id
  WHERE ce.itemid IN (220052, 220181, 223761)  -- Arterial/Noninvasive MAP
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= fe.intime
    AND ce.charttime < TIMESTAMP_ADD(fe.intime, INTERVAL 24 HOUR)
)
SELECT
  AVG(valuenum) AS avg_map_first24h
FROM map_events;