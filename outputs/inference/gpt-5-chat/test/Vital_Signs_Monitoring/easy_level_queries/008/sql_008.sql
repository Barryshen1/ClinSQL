WITH male_52_62 AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M'
    AND anchor_age BETWEEN 52 AND 62
),
resp_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%respiratory rate%'
),
rr_events AS (
  SELECT
    ce.subject_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN resp_itemids ri
    ON ce.itemid = ri.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
    ON ce.subject_id = icu.subject_id
    AND ce.stay_id = icu.stay_id
  JOIN male_52_62 m
    ON ce.subject_id = m.subject_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime BETWEEN icu.intime AND icu.outtime
)
SELECT
  MAX(valuenum) AS max_respiratory_rate
FROM (
  SELECT
    subject_id,
    stay_id,
    valuenum,
    DATETIME_DIFF(charttime, intime, DAY) AS icu_day
  FROM rr_events
) sub
WHERE icu_day >= 2;