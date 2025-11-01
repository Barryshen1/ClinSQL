WITH patient_filter AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 46 AND 56
),
icu_stays AS (
  SELECT i.stay_id, i.subject_id, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays` i
  INNER JOIN patient_filter p ON i.subject_id = p.subject_id
),
temp_measurements AS (
  SELECT c.valuenum, c.charttime, i.intime
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  INNER JOIN icu_stays i ON c.stay_id = i.stay_id
  WHERE c.itemid = 223761  
  AND c.charttime BETWEEN i.intime AND TIMESTAMP_ADD(i.intime, INTERVAL 24 HOUR)
)
SELECT APPROX_QUANTILES(valuenum, 100)[OFFSET(50)] AS median_temperature
FROM temp_measurements;