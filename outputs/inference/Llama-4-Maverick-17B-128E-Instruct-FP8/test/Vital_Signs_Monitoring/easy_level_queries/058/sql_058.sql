WITH 
relevant_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 74 AND 84
),
temp_itemid AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Temperature%' AND (label LIKE '%°F%' OR label LIKE '%Fahrenheit%')
),
min_temps AS (
  SELECT 
    ce.stay_id,
    MIN(ce.valuenum) AS min_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN relevant_patients rp ON ce.subject_id = rp.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.stay_id = icu.stay_id
  JOIN temp_itemid ti ON ce.itemid = ti.itemid
  WHERE ce.valuenum IS NOT NULL
  GROUP BY ce.stay_id
)
SELECT 
  APPROX_QUANTILES(min_temp, 1000)[OFFSET(500)] AS median_min_temp
FROM min_temps;