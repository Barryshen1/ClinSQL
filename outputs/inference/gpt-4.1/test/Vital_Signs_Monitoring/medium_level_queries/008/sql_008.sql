WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),

cohort AS (
  SELECT
    icu.stay_id,
    icu.subject_id,
    icu.hadm_id,
    icu.intime,
    icu.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND pat.anchor_age BETWEEN 39 AND 49
),

map_first24hr AS (
  SELECT
    c.stay_id,
    AVG(ce.valuenum) AS mean_map_24hr
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
    AND ce.charttime < DATETIME_ADD(c.intime, INTERVAL 24 HOUR)
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  GROUP BY c.stay_id
  HAVING COUNT(ce.valuenum) > 0
),

percentile AS (
  SELECT
    COUNTIF(mean_map_24hr < 75) AS num_below,
    COUNT(*) AS total
  FROM map_first24hr
)

SELECT
  SAFE_DIVIDE(num_below, total) * 100 AS percentile_75mmHg
FROM percentile;