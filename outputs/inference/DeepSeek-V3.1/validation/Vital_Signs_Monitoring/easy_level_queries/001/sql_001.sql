WITH first_map AS (
  SELECT 
    ie.stay_id,
    FIRST_VALUE(ce.valuenum) OVER (
      PARTITION BY ie.stay_id 
      ORDER BY ce.charttime
      ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
    ) AS first_map_value
  FROM `physionet-data.mimiciv_3_1_icu.icustays` ie
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON ie.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce 
    ON ie.stay_id = ce.stay_id
  WHERE 
    p.gender = 'M'
    AND p.anchor_age BETWEEN 52 AND 62
    AND ce.itemid IN (220181, 220052)  -- MAP itemids
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= ie.intime  -- Ensure measurement during the stay
  QUALIFY ROW_NUMBER() OVER (PARTITION BY ie.stay_id ORDER BY ce.charttime) = 1
)
SELECT 
  PERCENTILE_CONT(first_map_value, 0.25) OVER() AS q1,
  PERCENTILE_CONT(first_map_value, 0.75) OVER() AS q3,
  PERCENTILE_CONT(first_map_value, 0.75) OVER() - PERCENTILE_CONT(first_map_value, 0.25) OVER() AS iqr
FROM first_map
LIMIT 1;