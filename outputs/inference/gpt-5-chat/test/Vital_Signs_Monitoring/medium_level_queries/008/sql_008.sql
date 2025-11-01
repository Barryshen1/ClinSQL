WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean%'
    AND LOWER(label) LIKE '%pressure%'
    AND LOWER(category) LIKE '%vital%'
),
map_first24_per_stay AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    ce.stay_id,
    AVG(ce.valuenum) AS mean_map_24h
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
  JOIN map_itemids mi
    ON ce.itemid = mi.itemid
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS icu
    ON ce.stay_id = icu.stay_id
  WHERE ce.valuenum IS NOT NULL
    AND ce.charttime >= icu.intime
    AND ce.charttime < TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
  GROUP BY ce.subject_id, ce.hadm_id, ce.stay_id
),
demo_filtered AS (
  SELECT
    m.*,
    p.gender,
    p.anchor_age
  FROM map_first24_per_stay m
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON m.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
)
SELECT
  COUNTIF(mean_map_24h <= 75) / COUNT(*) * 100 AS percentile_75mmHg
FROM demo_filtered;