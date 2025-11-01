WITH temp_averages AS (
  SELECT
    icustays.stay_id,
    AVG(chartevents.valuenum) AS avg_temp
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icustays
    ON chartevents.stay_id = icustays.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  WHERE
    patients.gender = 'M'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 67 AND 77
    AND chartevents.itemid = 223761  -- Temperature in Celsius
    AND chartevents.charttime BETWEEN icustays.intime AND icustays.intime + INTERVAL '24' HOUR
    AND chartevents.valuenum IS NOT NULL
  GROUP BY icustays.stay_id
)
SELECT
  SUM(CASE WHEN avg_temp <= 36.0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS percentile
FROM temp_averages;