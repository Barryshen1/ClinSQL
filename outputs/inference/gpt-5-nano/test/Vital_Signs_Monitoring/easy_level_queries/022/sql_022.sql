WITH map_measurements AS (
  SELECT
    s.stay_id,
    ce.valuenum AS map_value
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS s
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = s.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` AS ce
    ON ce.subject_id = s.subject_id
   AND ce.hadm_id = s.hadm_id
   AND ce.stay_id = s.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` AS di
    ON di.itemid = ce.itemid
  WHERE p.gender = 'Male'
    AND p.anchor_age BETWEEN 48 AND 58
    AND LOWER(di.label) LIKE '%mean arterial pressure%'
    AND ce.valuenum IS NOT NULL
)
SELECT AVG(max_map) AS avg_max_map
FROM (
  SELECT stay_id, MAX(map_value) AS max_map
  FROM map_measurements
  GROUP BY stay_id
) AS per_stay;