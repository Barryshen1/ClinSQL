WITH filtered_icu_stays AS (
  SELECT 
    ie.stay_id,
    ie.subject_id,
    ie.intime,
    p.gender,
    p.anchor_age,
    p.anchor_year
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON ie.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age + (EXTRACT(YEAR FROM ie.intime) - p.anchor_year) 
        BETWEEN 85 AND 95
),
first_24h_map AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS map_value
  FROM filtered_icu_stays fis
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON fis.stay_id = ce.stay_id
    AND ce.charttime 
        BETWEEN fis.intime 
        AND DATETIME_ADD(fis.intime, INTERVAL 24 HOUR)
    AND ce.itemid IN (220052, 220181)  -- MAP item IDs
    AND ce.valuenum IS NOT NULL  -- Ensure numeric values
),
mean_map_per_stay AS (
  SELECT 
    stay_id,
    AVG(map_value) AS mean_map
  FROM first_24h_map
  GROUP BY stay_id
)
SELECT 
  STDDEV(mean_map) AS std_dev_first_24h_map
FROM mean_map_per_stay;