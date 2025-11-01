WITH 
eligible_patients AS (
  SELECT subject_id 
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 48 AND 58
),
eligible_icustays AS (
  SELECT i.stay_id, i.subject_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN eligible_patients p ON i.subject_id = p.subject_id
),
map_itemid AS (
  SELECT itemid FROM `physionet-data.mimiciv_3_1_icu.d_items` WHERE label = 'Mean Arterial Pressure'
),
map_measurements AS (
  SELECT e.stay_id, c.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN eligible_icustays e ON c.stay_id = e.stay_id
  WHERE c.itemid = (SELECT itemid FROM map_itemid)
),
max_map_per_stay AS (
  SELECT stay_id, MAX(valuenum) AS max_map
  FROM map_measurements
  GROUP BY stay_id
)
SELECT AVG(max_map) AS avg_max_map
FROM max_map_per_stay;