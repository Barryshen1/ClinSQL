WITH eligible_stays AS (
  -- Select qualifying ICU stays for males aged 52-62
  SELECT 
    icu.subject_id,
    icu.stay_id,
    icu.intime
  FROM 
    `physionet-data.mimiciv_3_1_icu.icustays` icu
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` pat
  ON 
    icu.subject_id = pat.subject_id
  WHERE 
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND icu.los > 0  -- Exclude invalid stays
),
first_map AS (
  -- Get first MAP per eligible stay
  SELECT 
    stay.subject_id,
    stay.stay_id,
    ce.charttime,
    ce.valuenum AS map_value
  FROM 
    eligible_stays stay
  INNER JOIN 
    `physionet-data.mimiciv_3_1_icu.chartevents` ce
  ON 
    stay.subject_id = ce.subject_id
    AND stay.stay_id = ce.stay_id
    AND ce.itemid = 220052  -- MAP itemid
    AND ce.valuenum IS NOT NULL
  WHERE 
    ce.charttime >= stay.intime  -- After ICU admission
  QUALIFY 
    ROW_NUMBER() OVER (PARTITION BY stay.stay_id ORDER BY ce.charttime ASC) = 1
)
-- Compute IQR of first MAP values
SELECT 
  PERCENTILE_CONT(map_value, 0.75) - PERCENTILE_CONT(map_value, 0.25) AS iqr_first_map
FROM 
  first_map
WHERE 
  map_value IS NOT NULL;