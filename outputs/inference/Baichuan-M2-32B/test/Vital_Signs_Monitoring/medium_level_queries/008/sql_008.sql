WITH map_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE (label LIKE '%Mean Arterial Pressure%' OR label LIKE '%MAP%')
    AND unitname = 'mmHg'
),
cohort_stays AS (
  SELECT 
    i.stay_id,
    i.subject_id,
    i.hadm_id,
    i.intime,
    p.gender,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 39 AND 49
),
map_readings AS (
  SELECT 
    cs.stay_id,
    ce.valuenum AS map_value
  FROM cohort_stays cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cs.subject_id = ce.subject_id
    AND cs.hadm_id = ce.hadm_id
    AND cs.stay_id = ce.stay_id
    AND ce.charttime BETWEEN cs.intime AND TIMESTAMP_ADD(cs.intime, INTERVAL 24 HOUR)
  WHERE ce.itemid IN (SELECT itemid FROM map_itemids)
    AND ce.valuenum IS NOT NULL
),
avg_map_per_stay AS (
  SELECT 
    stay_id,
    AVG(map_value) AS avg_map
  FROM map_readings
  GROUP BY stay_id
)
SELECT 
  (COUNT(CASE WHEN avg_map <= 75 THEN 1 END) * 100.0) / NULLIF(COUNT(*), 0) AS percentile
FROM avg_map_per_stay;