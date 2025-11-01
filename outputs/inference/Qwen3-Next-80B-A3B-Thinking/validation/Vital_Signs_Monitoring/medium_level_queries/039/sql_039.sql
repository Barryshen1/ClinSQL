WITH eligible_stays AS (
  SELECT i.stay_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 83 AND 93
),
map_measurements AS (
  SELECT c.stay_id, c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN eligible_stays e
    ON c.stay_id = e.stay_id
  WHERE c.itemid = 52
    AND c.charttime BETWEEN e.intime AND e.intime + INTERVAL 48 HOUR
    AND c.valuenum IS NOT NULL
),
avg_map_per_stay AS (
  SELECT stay_id, AVG(valuenum) AS avg_map
  FROM map_measurements
  GROUP BY stay_id
  HAVING COUNT(*) >= 3
)
SELECT
  COUNTIF(avg_map <= 60) * 100.0 / NULLIF(COUNT(*), 0) AS percentile
FROM avg_map_per_stay;