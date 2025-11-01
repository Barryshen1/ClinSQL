WITH averages AS (
  SELECT 
    icustays.stay_id,
    AVG(chartevents.valuenum) AS avg_rr
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` chartevents
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icustays
    ON chartevents.stay_id = icustays.stay_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` patients
    ON icustays.subject_id = patients.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d_items
    ON chartevents.itemid = d_items.itemid
  WHERE 
    d_items.label = 'Respiratory Rate'
    AND chartevents.charttime BETWEEN icustays.intime AND icustays.intime + INTERVAL 48 HOUR
    AND patients.gender = 'M'
    AND (patients.anchor_age + EXTRACT(YEAR FROM icustays.intime) - patients.anchor_year) BETWEEN 68 AND 78
  GROUP BY icustays.stay_id
)
SELECT 
  (COUNTIF(avg_rr <= 12) * 100.0) / COUNT(*) AS percentile
FROM averages;