WITH cohort_stays AS (
  SELECT 
    i.stay_id, 
    i.intime, 
    i.outtime,
    p.gender, 
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 58 AND 68
),
map_data AS (
  SELECT 
    cs.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM cohort_stays cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ce.stay_id = cs.stay_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.d_items` di
    ON ce.itemid = di.itemid
  WHERE di.category = 'Routine Vital Signs'
    AND (LOWER(di.label) LIKE '%map%' OR LOWER(di.label) LIKE '%mean%')
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
    AND ce.charttime >= cs.intime
    AND ce.charttime < DATETIME_ADD(cs.intime, INTERVAL 48 HOUR)
  GROUP BY cs.stay_id
  HAVING COUNT(ce.valuenum) > 0
)
SELECT 
  COUNTIF(mean_map <= 85) * 100.0 / COUNT(*) AS percentile
FROM map_data;