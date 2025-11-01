WITH filtered_stays AS (
  SELECT 
    i.stay_id,
    i.intime,
    i.outtime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON i.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) BETWEEN 48 AND 58
),
map_per_stay AS (
  SELECT 
    s.stay_id,
    MAX(c.valuenum) AS max_map
  FROM filtered_stays s
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` c
    ON s.stay_id = c.stay_id
  WHERE 
    c.itemid = 220052  -- MAP itemid
    AND c.charttime >= s.intime
    AND c.charttime <= s.outtime
    AND c.valuenum IS NOT NULL  -- Ensure numeric values
  GROUP BY s.stay_id
)
SELECT 
  AVG(max_map) AS avg_max_map
FROM map_per_stay;