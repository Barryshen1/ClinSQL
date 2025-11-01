WITH averages AS (
  SELECT
    AVG(chartevents.valuenum) AS avg_sbp
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON icustays.stay_id = chartevents.stay_id
  WHERE
    patients.gender = 'F'
    AND (patients.anchor_age + (EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year)) BETWEEN 38 AND 48
    AND chartevents.itemid = 220050
    AND chartevents.valuenum IS NOT NULL
    AND chartevents.charttime BETWEEN icustays.intime AND TIMESTAMP_ADD(icustays.intime, INTERVAL 24 HOUR)
  GROUP BY icustays.stay_id
)
SELECT
  (COUNTIF(avg_sbp <= 120) * 100.0) / COUNT(*) AS percentile
FROM averages;