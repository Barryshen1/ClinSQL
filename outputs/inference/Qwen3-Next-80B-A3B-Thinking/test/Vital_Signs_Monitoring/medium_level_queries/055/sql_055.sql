WITH avg_spo2_per_stay AS (
  SELECT 
    icustays.stay_id,
    AVG(chartevents.valuenum) AS avg_spo2
  FROM `physionet-data.mimiciv_3_1_icu.icustays` icustays
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
    ON icustays.stay_id = chartevents.stay_id
  WHERE 
    patients.gender = 'F'
    AND chartevents.itemid = 220277
    AND chartevents.charttime BETWEEN icustays.intime AND icustays.intime + INTERVAL 24 HOUR
    AND (EXTRACT(YEAR FROM icustays.intime) - (patients.anchor_year - patients.anchor_age)) BETWEEN 87 AND 97
  GROUP BY icustays.stay_id
)
SELECT 
  (COUNTIF(avg_spo2 <= 88) * 100.0) / COUNT(*) AS percentile
FROM avg_spo2_per_stay;