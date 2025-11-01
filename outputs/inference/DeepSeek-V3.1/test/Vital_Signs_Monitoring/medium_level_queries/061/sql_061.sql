WITH cohort_stays AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.hadm_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 38 AND 48
),

map_per_stay AS (
  SELECT 
    cs.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM cohort_stays cs
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON cs.stay_id = ce.stay_id
  WHERE ce.itemid IN (220181, 220052)  -- MAP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.valuenum > 0
  GROUP BY cs.stay_id
)

SELECT 
  COUNT(*) AS total_stays,
  SUM(CASE WHEN avg_map <= 60 THEN 1 ELSE 0 END) AS stays_below_60,
  SAFE_DIVIDE(
    SUM(CASE WHEN avg_map <= 60 THEN 1 ELSE 0 END),
    COUNT(*)
  ) AS percentile_rank
FROM map_per_stay;