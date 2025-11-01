WITH icu_male_85_95 AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 85 AND 95
)

, map_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  WHERE
    ce.itemid IN (220052, 220181) -- MAP itemids
    AND ce.valuenum IS NOT NULL
)

, map_first_24h AS (
  SELECT
    icu.stay_id,
    AVG(me.valuenum) AS mean_map_24h
  FROM
    icu_male_85_95 icu
  INNER JOIN
    map_events me
    ON icu.stay_id = me.stay_id
    AND me.charttime >= icu.intime
    AND me.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY
    icu.stay_id
)

SELECT
  STDDEV_SAMP(mean_map_24h) AS stddev_mean_map_24h
FROM
  map_first_24h
WHERE
  mean_map_24h IS NOT NULL;