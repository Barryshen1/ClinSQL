WITH cohort AS (
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime
  FROM
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON
    icu.subject_id = pat.subject_id
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 85 AND 95
),
map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
first_24hr_map AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM
    cohort c
  JOIN
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON
    c.stay_id = ce.stay_id
  JOIN
    map_items m
  ON
    ce.itemid = m.itemid
  WHERE
    ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY
    c.stay_id
)
SELECT
  STDDEV(mean_map) AS stddev_first_24hr_map
FROM
  first_24hr_map;