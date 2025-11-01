WITH population_stays AS (
  SELECT 
    i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 38 AND 48
),
stay_avg_map AS (
  SELECT 
    ps.stay_id,
    AVG(ce.valuenum) AS avg_map
  FROM population_stays ps
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON ps.stay_id = ce.stay_id
  WHERE ce.itemid IN (52, 456)  -- MAP itemids (invasive/non-invasive)
    AND ce.valuenum IS NOT NULL
  GROUP BY ps.stay_id
)
SELECT 
  SAFE_DIVIDE(
    COUNTIF(avg_map <= 60),
    COUNT(*)
  ) AS proportion
FROM stay_avg_map;