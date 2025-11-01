WITH map_averages AS (
  SELECT
    icustays.stay_id,
    AVG(chartevents.valuenum) AS mean_map
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON icustays.stay_id = chartevents.stay_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d_items
    ON chartevents.itemid = d_items.itemid
  WHERE
    patients.gender = 'M'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 85 AND 95
    AND d_items.label = 'MAP'
    AND chartevents.charttime >= icustays.intime
    AND chartevents.charttime < icustays.intime + INTERVAL 24 HOUR
    AND chartevents.valuenum IS NOT NULL
  GROUP BY icustays.stay_id
)
SELECT STDDEV(mean_map) AS std_dev_map
FROM map_averages;