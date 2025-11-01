WITH cohort AS (
  SELECT 
    icu.stay_id,
    icu.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` AS icu
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    ON icu.subject_id = pat.subject_id
  WHERE pat.gender = 'M'
    AND (pat.anchor_age + (EXTRACT(YEAR FROM icu.intime) - pat.anchor_year)) BETWEEN 52 AND 62
),
first_map AS (
  SELECT 
    c.stay_id,
    ce.valuenum AS map_value
  FROM cohort c
  INNER JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
    ON c.stay_id = ce.stay_id
  WHERE ce.itemid = 220052
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= c.intime
  QUALIFY ROW_NUMBER() OVER (PARTITION BY c.stay_id ORDER BY ce.charttime) = 1
)
SELECT 
  APPROX_QUANTILES(map_value, 1000)[OFFSET(750)] - APPROX_QUANTILES(map_value, 1000)[OFFSET(250)] AS iqr
FROM first_map;