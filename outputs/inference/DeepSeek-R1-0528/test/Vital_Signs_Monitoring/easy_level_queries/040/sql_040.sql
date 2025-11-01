WITH eligible_stays AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year BETWEEN 55 AND 65
)
, first_map AS (
  SELECT 
    ce.stay_id,
    ce.valuenum AS first_map_value
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN eligible_stays es
    ON ce.stay_id = es.stay_id
  WHERE 
    ce.itemid IN (220052, 220181)  -- MAP item IDs
    AND ce.valuenum IS NOT NULL    -- Ensure numeric value exists
    AND ce.charttime >= es.intime  -- Measurement during ICU stay
  QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ce.stay_id 
    ORDER BY ce.charttime
  ) = 1  -- First measurement per stay
)
SELECT 
  STDDEV(first_map_value) AS sd_first_map
FROM first_map;