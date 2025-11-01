WITH temp_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_icu.d_items`
  WHERE label LIKE '%Temp%' 
    AND unitname = 'F'
),
eligible_patients AS (
  SELECT DISTINCT p.subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON p.subject_id = i.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 86 AND 96
),
temp_readings AS (
  SELECT ce.valuenum
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  INNER JOIN `physionet-data.mimiciv_3_1_icu.icustays` i ON ce.subject_id = i.subject_id AND ce.stay_id = i.stay_id
  INNER JOIN eligible_patients ep ON i.subject_id = ep.subject_id
  CROSS JOIN temp_items ti
  WHERE ce.itemid = ti.itemid
    AND ce.valuenum IS NOT NULL
    AND ce.charttime >= i.intime
    AND ce.charttime < TIMESTAMP_ADD(i.intime, INTERVAL 1 DAY)
)
SELECT 
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75_temperature_f
FROM temp_readings;