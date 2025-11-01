WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
map_events AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    ce.charttime,
    ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
),
stay_mean_map AS (
  SELECT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    AVG(me.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  JOIN map_events me
    ON ie.subject_id = me.subject_id
    AND ie.stay_id = me.stay_id
    AND me.charttime >= ie.intime
    AND me.charttime < DATETIME_ADD(ie.intime, INTERVAL 48 HOUR)
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
  GROUP BY ie.subject_id, ie.hadm_id, ie.stay_id
),
percentile_calc AS (
  SELECT
    COUNTIF(mean_map <= 85) / NULLIF(COUNT(*), 0) * 100 AS percentile_rank
  FROM stay_mean_map
)
SELECT percentile_rank
FROM percentile_calc;