WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 85 AND 95
),
map_events AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE LOWER(di.label) LIKE '%mean arterial pressure%'
    AND ce.valuenum IS NOT NULL
),
first24h_map AS (
  SELECT
    c.stay_id,
    AVG(me.valuenum) AS mean_map_24h
  FROM cohort c
  JOIN map_events me
    ON c.subject_id = me.subject_id
   AND c.stay_id = me.stay_id
   AND me.charttime >= c.intime
   AND me.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  GROUP BY c.stay_id
)
SELECT
  STDDEV(mean_map_24h) AS stddev_mean_map_24h
FROM first24h_map;