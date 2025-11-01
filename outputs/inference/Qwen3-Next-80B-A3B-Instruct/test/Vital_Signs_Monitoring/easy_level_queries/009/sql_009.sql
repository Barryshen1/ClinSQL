SELECT PERCENTILE_CONT(chartevents.valuenum, 0.75) AS p75_temperature_fahrenheit
FROM physionet-data.mimiciv_3_1_hosp.patients AS patients
JOIN physionet-data.mimiciv_3_1_icu.icustays AS icustays
  ON patients.subject_id = icustays.subject_id
JOIN physionet-data.mimiciv_3_1_icu.chartevents AS chartevents
  ON icustays.stay_id = chartevents.stay_id
JOIN physionet-data.mimiciv_3_1_icu.d_items AS d_items
  ON chartevents.itemid = d_items.itemid
WHERE patients.gender = 'F'
  AND patients.anchor_age BETWEEN 86 AND 96
  AND LOWER(d_items.label) LIKE '%temperature%'
  AND chartevents.valueuom = 'F'
  AND chartevents.charttime >= icustays.intime
  AND chartevents.charttime <= icustays.intime + INTERVAL 24 HOUR
  AND chartevents.valuenum IS NOT NULL
  AND chartevents.valuenum BETWEEN 80 AND 115;