WITH filtered_stays AS (
  SELECT i.stay_id
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 38 AND 48
),
avg_map_per_stay AS (
  SELECT fs.stay_id,
         AVG(ce.valuenum) AS avg_map
  FROM filtered_stays fs
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fs.stay_id = ce.stay_id
  WHERE ce.itemid = 52  -- Mean Arterial Pressure
    AND ce.valuenum IS NOT NULL
  GROUP BY fs.stay_id
)
SELECT 
  SUM(CASE WHEN avg_map <= 60 THEN 1 ELSE 0 END) / COUNT(*) AS percentile_rank
FROM avg_map_per_stay;