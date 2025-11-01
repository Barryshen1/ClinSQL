WITH cohort AS (
  SELECT 
    i.stay_id,
    i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year)) BETWEEN 58 AND 68
),
mean_maps AS (
  SELECT 
    c.stay_id,
    AVG(ce.valuenum) AS mean_map
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 52
    AND ce.charttime BETWEEN c.intime AND c.intime + INTERVAL 48 HOUR
    AND ce.valuenum IS NOT NULL
  GROUP BY c.stay_id
)
SELECT 
  (COUNTIF(mean_map <= 85) * 100.0) / NULLIF(COUNT(*), 0) AS percentile
FROM mean_maps;