WITH cohort AS (
  SELECT p.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 82 AND 92
),
map_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE LOWER(label) LIKE '%mean arterial pressure%'
),
map_events AS (
  SELECT ce.subject_id, ce.hadm_id, ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN map_items mi
    ON ce.itemid = mi.itemid
  WHERE ce.valuenum IS NOT NULL
),
max_map_per_stay AS (
  SELECT c.hadm_id, MAX(me.valuenum) AS max_map
  FROM cohort c
  JOIN map_events me
    ON c.subject_id = me.subject_id
   AND c.hadm_id = me.hadm_id
  GROUP BY c.hadm_id
)
SELECT
  PERCENTILE_CONT(max_map, 0.5) OVER() AS median_of_max_map
FROM max_map_per_stay
LIMIT 1;